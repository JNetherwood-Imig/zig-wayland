const std = @import("std");
const wire = @import("wire.zig");
const Connection = @import("Connection.zig");
const Allocator = std.mem.Allocator;

/// Construct a message handler to handle messages present in the `protocol` type.
/// This makes it possible to generate code for custom protocols and pass the resulting type here
/// to achieve full extensibility.
pub fn IncomingMessageHandler(comptime IncomingMessage: type) type {
    return struct {
        const Self = @This();

        /// List of currently tracked objects
        proxies: std.ArrayList(Proxy),

        /// Tracks an object and its interface, used for decoding messages
        pub const Proxy = struct {
            id: u32,
            interface: [:0]const u8,
        };

        /// Initialize an unbounded message handler with an allocator and ititial capacity
        pub fn initCapacity(gpa: Allocator, initial_capacity: usize) Allocator.Error!Self {
            return .{ .proxies = try .initCapacity(gpa, initial_capacity) };
        }

        /// Initialize a bounded message handler which does not invoke the heap.
        /// When initializing this way, always use addObjectBounded instead of addObject
        /// because an allocator cannot be used.
        pub fn initBuffered(buffer: []Proxy) Self {
            return .{ .proxies = .initBuffer(buffer) };
        }

        /// Free the underlying list of proxies if initialized using `initCapacity`
        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.proxies.deinit(gpa);
        }

        pub const AddObjectError = error{OutOfMemory};

        /// Add an object to an unbounded message handler.
        /// NOTE: Must have been initialized with `initCapacity`,
        /// it is invalid to use this function with `initBuffered`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObject(self: *Self, gpa: Allocator, object: anytype) AddObjectError!void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.append(gpa, proxy);
        }

        /// Add an object to the message handler, failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObjectBounded(self: *Self, object: anytype) AddObjectError!void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.appendBounded(proxy);
        }

        /// Add a raw id and associated interface to the message handler.
        /// NOTE: Must have been initialized with `initCapacity`,
        /// it is invalid to use this function with `initBuffered`
        pub fn addRaw(
            self: *Self,
            gpa: Allocator,
            id: u32,
            interface: [:0]const u8,
        ) AddObjectError!void {
            try self.proxies.append(gpa, .{ .id = id, .interface = interface });
        }

        /// Add a raw id and associated interface to the message handler,
        /// failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        pub fn addRawBounded(self: *Self, id: u32, interface: [:0]const u8) AddObjectError!void {
            try self.proxies.appendBounded(.{ .id = id, .interface = interface });
        }

        /// Remove an object from the handler.
        /// `object` can be either a wayland object from a factory interface
        /// or `IdAllocator` or a raw integer id.
        pub fn delObject(self: *Self, object: anytype) void {
            const id = switch (@typeInfo(@TypeOf(object))) {
                .int => object,
                .@"enum" => object.getId(),
                else => @compileError("Unsupported type."),
            };

            for (self.proxies.items, 0..) |proxy, i| {
                if (proxy.id == id) {
                    _ = self.proxies.swapRemove(i);
                    return;
                }
            }
        }

        pub const GetMessageError = Connection.FlushError || Connection.PollEventsError;

        /// Try to get an message from the `connection`,
        /// immediately returning `null` if the buffers are empty and the socket is not readable.
        pub fn getNextMessage(
            self: *Self,
            connection: *Connection,
        ) GetMessageError!?IncomingMessage {
            return self.nextMessage(connection, false);
        }

        /// Wait indefinately for an message to be received.
        pub fn waitNextMessage(
            self: *Self,
            connection: *Connection,
        ) GetMessageError!IncomingMessage {
            while (true) {
                if (try self.nextMessage(connection, true)) |ev| return ev;
            }
        }

        fn nextMessage(
            self: *Self,
            conn: *Connection,
            wait: bool,
        ) GetMessageError!?IncomingMessage {
            // Always start by flushing buffered messages
            conn.flush() catch |err| switch (err) {
                error.BrokenPipe => {},
                else => |e| return e,
            };

            while (true) {
                // Try to get a header, otherwise poll for messages,
                // returning null if polling times out
                const header = conn.reader.nextHeader() orelse {
                    if (!try conn.pollEvents(wait)) return null;
                    continue;
                };

                const msg_len = header.length - @sizeOf(wire.Header);
                var buf: [4096]u8 = undefined;
                std.debug.assert(conn.reader.getData(buf[0..msg_len]) == msg_len);

                // When we find the appropriate proxy, use its interface to lookup the associated
                // message types and deserialize the message
                for (self.proxies.items) |proxy| {
                    if (proxy.id == header.object) {
                        return deserializeMessage(
                            IncomingMessage,
                            header,
                            proxy.interface,
                            buf[0..msg_len],
                            conn,
                        );
                    }
                }
            }
        }
    };
}

fn deserializeMessage(
    comptime Message: type,
    header: wire.Header,
    target_interface: [:0]const u8,
    bytes: []const u8,
    conn: *Connection,
) Message {
    // This is arbitrary, but works for now.
    @setEvalBranchQuota(10000);

    const ti = @typeInfo(Message).@"union";
    inline for (ti.fields) |field| if (std.mem.eql(u8, field.name, target_interface)) {
        const sub_fields = @typeInfo(field.type).@"union".fields;
        // Since sub_fields cannot be indexed with a runtime value (header.opcode),
        // this seems to be the best alternative.
        switch (header.opcode) {
            inline 0...sub_fields.len - 1 => |i| {
                const sub_field = sub_fields[i];

                // Get fds from connection
                const fd_count = comptime countFds(sub_field.type);
                var fds: [fd_count]std.posix.fd_t = undefined;
                // FIXME: Is there good reason to handle the null case gracefully?
                // What could that even look like this far in?
                for (0..fd_count) |fd_index| fds[fd_index] = conn.reader.nextFd().?;

                // Deserialize the message packet and create an *Message struct
                // (e.g. wayland.Display.DeleteIdMessage)
                var message: sub_field.type = wire.deserializeMessage(sub_field.type, bytes, &fds);

                // Since the target object is derived from the header,
                // rather than the message signature, it is set after deserializing
                const object_self_field = std.meta.fields(@TypeOf(message))[0];
                @field(message, object_self_field.name) = @enumFromInt(header.object);

                // Initialize the interface-level message struct (e.g. Message.wl_display)
                const interface_message = @unionInit(field.type, sub_field.name, message);

                return @unionInit(Message, field.name, interface_message);
            },
            else => @panic("Invalid opcode."),
        }
    };

    // One of the proxies was created with an interface
    // that doesn't exist in the given set of protocols
    unreachable;
}

fn countFds(comptime T: type) usize {
    var count: usize = 0;
    for (T._signature) |byte| {
        if (byte == 'f') count += 1;
    }
    return count;
}
