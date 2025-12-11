const std = @import("std");
const core = @import("core");
const wire = core.wire;
const Allocator = std.mem.Allocator;
const Connection = core.Connection;

/// Construct an event handler to handle events present in the `protocol` type.
/// This makes it possible to generate code for custom protocols and pass the resulting type here
/// to achieve full extensibility.
pub fn EventHandler(comptime protocol: type) type {
    return struct {
        const Self = @This();

        /// List of currently tracked objects
        proxies: std.ArrayList(Proxy),

        /// Tracks an object and its interface, used for decoding events
        pub const Proxy = struct {
            id: u32,
            interface: [:0]const u8,
        };

        /// Initialize an unbounded event handler with an allocator and ititial capacity
        pub fn initCapacity(gpa: Allocator, initial_capacity: usize) Allocator.Error!Self {
            return .{ .proxies = try .initCapacity(gpa, initial_capacity) };
        }

        /// Initialize a bounded event handler which does not invoke the heap.
        /// When initializing this way, always use addObjectBounded instead of addObject
        /// because an allocator cannot be used.
        pub fn initBuffered(buffer: []Proxy) Self {
            return .{ .proxies = .initBuffer(buffer) };
        }

        /// Free the underlying list of proxies if initialized using `initCapacity`
        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.proxies.deinit(gpa);
        }

        /// Add an object to an unbounded event handler.
        /// NOTE: Must have been initialized with `initCapacity`,
        /// it is invalid to use this function with `initBuffered`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObject(self: *Self, gpa: Allocator, object: anytype) error{OutOfMemory}!void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.append(gpa, proxy);
        }

        /// Add an object to the event handler, failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObjectBounded(self: *Self, object: anytype) error{OutOfMemory}!void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.appendBounded(proxy);
        }

        /// Add a raw id and associated interface to the event handler.
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

        /// Add a raw id and associated interface to the event handler,
        /// failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        pub fn addRawBounded(self: *Self, id: u32, interface: [:0]const u8) AddObjectError!void {
            try self.proxies.appendBounded(.{ .id = id, .interface = interface });
        }

        pub const AddObjectError = error{OutOfMemory};

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

        /// Try to get an event from the `connection`,
        /// immediately returning `null` if the buffers are empty and the socket is not readable.
        pub fn getNextEvent(
            self: *const Self,
            connection: *Connection,
        ) GetEventError!?protocol.Event {
            return self.nextEvent(connection, false);
        }

        /// Wait for an event to be received
        pub fn waitNextEvent(
            self: *const Self,
            connection: *Connection,
        ) GetEventError!protocol.Event {
            while (true) {
                if (try self.nextEvent(connection, true)) |ev| return ev;
            }
        }

        pub const GetEventError = Connection.FlushError || Connection.PollEventsError;

        fn nextEvent(
            self: *const Self,
            conn: *Connection,
            wait: bool,
        ) GetEventError!?protocol.Event {
            // Always start by flushing buffered messages
            conn.flush() catch |err| switch (err) {
                error.BrokenPipe => {},
                else => |e| return e,
            };

            while (true) {
                // Try to get a header, otherwise poll for events,
                // returning null if polling times out
                const header = conn.reader.nextHeader() orelse {
                    if (!try conn.pollEvents(wait)) return null;
                    continue;
                };

                const msg_len = header.length - @sizeOf(wire.Header);
                var buf: [4096]u8 = undefined;
                std.debug.assert(conn.reader.getData(buf[0..msg_len]) == msg_len);

                // When we find the appropriate proxy, use its interface to lookup the associated
                // event types and deserialize the event
                for (self.proxies.items) |proxy| if (proxy.id == header.object) {
                    return deserializeEvent(
                        protocol.Event,
                        header,
                        proxy.interface,
                        buf[0..msg_len],
                        conn,
                    );
                };
            }
        }
    };
}

fn deserializeEvent(
    comptime Event: type,
    header: wire.Header,
    target_interface: [:0]const u8,
    bytes: []const u8,
    conn: *Connection,
) Event {
    @setEvalBranchQuota(10000);
    const ti = @typeInfo(Event).@"union";
    inline for (ti.fields) |field| if (std.mem.eql(u8, field.name, target_interface)) {
        const sub_fields = @typeInfo(field.type).@"union".fields;
        switch (header.opcode) {
            inline 0...sub_fields.len - 1 => |i| {
                const sub_field = sub_fields[i];

                const fd_count = comptime countFds(sub_field.type);
                var fds: [fd_count]std.posix.fd_t = undefined;
                for (0..fd_count) |fd_index| fds[fd_index] = conn.reader.nextFd().?;

                var data: sub_field.type = wire.deserializeEventType(sub_field.type, bytes, &fds);
                @field(data, std.meta.fields(@TypeOf(data))[0].name) = @enumFromInt(header.object);

                const sub_ev = @unionInit(field.type, sub_field.name, data);
                const ev = @unionInit(Event, field.name, sub_ev);
                return ev;
            },
            else => @panic("Invalid opcode."),
        }
    };
    @panic("Invalid opcode");
}

fn countFds(comptime T: type) usize {
    var count: usize = 0;
    for (T._signature) |byte| {
        if (byte == 'f') count += 1;
    }
    return count;
}
