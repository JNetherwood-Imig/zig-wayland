const std = @import("std");
const wire = @import("wire.zig");
const Connection = @import("Connection.zig");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.wayland);

/// Constructs a message handler for the result of `MessageUnion`.
///
/// Example:
/// ```
/// const Event = MessageUnion(.{ wayland, xdg_shell });
/// const EventHandler = MessageHandler(Event);
///
/// pub fn main() !void {
///     ...
///     const handler = EventHandler.init(...);
///     ...
///     while (handler.waitNextMessage(...)) |event| switch (event) {
///         wl_display => |display_event| switch (display_event) {...},
///     } else |err| return err;
/// }
/// ```
pub fn MessageHandler(comptime Message: type) type {
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

        pub const GetMessageError = DeserializeError ||
            Connection.FlushError ||
            Connection.PollEventsError ||
            Connection.ReadIncomingError ||
            error{ TargetObjectNotFound, MessageTooLong };

        /// Try to get an message from the `connection`,
        /// immediately returning `null` if the buffers are empty and the socket is not readable.
        pub fn getNextMessage(self: *Self, connection: *Connection) GetMessageError!?Message {
            return self.nextMessage(connection, false);
        }

        /// Wait indefinately for an message to be received.
        pub fn waitNextMessage(self: *Self, connection: *Connection) GetMessageError!Message {
            while (true) if (try self.nextMessage(connection, true)) |ev| return ev;
        }

        fn nextMessage(
            self: *Self,
            conn: *Connection,
            wait: bool,
        ) GetMessageError!?Message {
            // Always start by flushing buffered messages
            conn.flush() catch |err| switch (err) {
                error.BrokenPipe => {},
                else => |e| return e,
            };

            outer: while (true) {
                // Try to get a header, otherwise poll for messages,
                // returning null if polling times out
                const header = conn.peekHeader() orelse {
                    conn.pollEvents(if (wait) -1 else 0) catch |err| switch (err) {
                        error.Timeout => return null,
                        else => |e| return e,
                    };
                    try conn.readIncoming();
                    continue :outer;
                };

                if (header.length > wire.libwayland_max_message_size)
                    return error.MessageTooLong;

                const message = conn.peek(header.length) orelse {
                    conn.pollEvents(if (wait) -1 else 0) catch |err| switch (err) {
                        error.Timeout => return null,
                        else => |e| return e,
                    };
                    try conn.readIncoming();
                    continue :outer;
                };
                const body = message[@sizeOf(wire.Header)..];

                // When we find the appropriate proxy, use its interface to lookup the associated
                // message types and deserialize the message
                for (self.proxies.items) |proxy| if (proxy.id == header.object) {
                    return try deserializeMessage(Message, header, proxy.interface, body, conn) orelse
                        continue :outer;
                };
                log.err("Got message for untracked object {d} (opcode {d}).", .{
                    header.object,
                    header.opcode,
                });
                return error.TargetObjectNotFound;
            }
        }
    };
}

const DeserializeError = wire.DeserializeError || error{ InvalidOpcode, InvalidInterface };

fn deserializeMessage(
    comptime Message: type,
    header: wire.Header,
    target_interface: [:0]const u8,
    bytes: []const u8,
    conn: *Connection,
) DeserializeError!?Message {
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
                const fd_count = countFds(sub_field.type);
                const fds = conn.peekFds(fd_count) orelse return null;

                // At this point, all possible read failures have been passed,
                // so we can finally discard consumed bytes.
                conn.discard(header.length);
                conn.discardFds(fd_count);

                // Deserialize the message packet and create an *Message struct
                // (e.g. wayland.Display.DeleteIdMessage)
                var message = try wire.deserializeMessage(sub_field.type, bytes, fds);

                // Since the target object is derived from the header,
                // rather than the message signature, it is set after deserializing
                const object_self_field = std.meta.fields(@TypeOf(message))[0];
                @field(message, object_self_field.name) = @enumFromInt(header.object);

                // Initialize the interface-level message struct (e.g. Message.wl_display)
                const interface_message = @unionInit(field.type, sub_field.name, message);

                return @unionInit(Message, field.name, interface_message);
            },
            else => return error.InvalidOpcode,
        }
    };

    return error.InvalidInterface;
}

fn countFds(comptime T: type) usize {
    var count: usize = 0;
    for (T._signature) |byte| {
        if (byte == 'd') count += 1;
    }
    return count;
}

test {
    const Message = @import("message_union.zig").MessageUnion(.{});
    const Handler = MessageHandler(Message);
    std.testing.refAllDeclsRecursive(Handler);
}
