const std = @import("std");
const wire = @import("wire.zig");
const Connection = @import("Connection.zig");
const IdAllocator = @import("IdAllocator.zig");
const Allocator = std.mem.Allocator;

/// Construct an event handler to handle events present in the `protocol` type.
/// This makes it possible to generate code for custom protocols and pass the resulting type here
/// to achieve full extensibility.
pub fn EventHandler(comptime Event: type) type {
    return struct {
        const Self = @This();

        /// List of currently tracked objects
        proxies: std.ArrayList(Proxy),
        ida: IdAllocator,

        /// Tracks an object and its interface, used for decoding events
        pub const Proxy = struct {
            id: u32,
            interface: [:0]const u8,
        };

        /// Initialize an unbounded event handler with an allocator and ititial capacity
        pub fn initCapacity(
            gpa: Allocator,
            ida: IdAllocator,
            initial_capacity: usize,
        ) Allocator.Error!Self {
            return .{ .proxies = try .initCapacity(gpa, initial_capacity), .ida = ida };
        }

        /// Initialize a bounded event handler which does not invoke the heap.
        /// When initializing this way, always use addObjectBounded instead of addObject
        /// because an allocator cannot be used.
        pub fn initBuffered(buffer: []Proxy, ida: IdAllocator) Self {
            return .{ .proxies = .initBuffer(buffer), .ida = ida };
        }

        /// Free the underlying list of proxies if initialized using `initCapacity`
        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.proxies.deinit(gpa);
        }

        pub const AddObjectError = error{OutOfMemory};

        /// Add an object to an unbounded event handler.
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

        /// Add an object to the event handler, failing if capacity is reached.
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

        pub const GetEventError = Connection.FlushError ||
            Connection.PollEventsError ||
            IdAllocator.FreeError ||
            error{ProtocolError};

        /// Try to get an event from the `connection`,
        /// immediately returning `null` if the buffers are empty and the socket is not readable.
        pub fn getNextEvent(
            self: *Self,
            connection: *Connection,
        ) GetEventError!?Event {
            return self.nextEvent(connection, false);
        }

        /// Wait indefinately for an event to be received.
        pub fn waitNextEvent(
            self: *Self,
            connection: *Connection,
        ) GetEventError!Event {
            while (true) {
                if (try self.nextEvent(connection, true)) |ev| return ev;
            }
        }

        fn nextEvent(
            self: *Self,
            conn: *Connection,
            wait: bool,
        ) GetEventError!?Event {
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
                const ev = for (self.proxies.items) |proxy| {
                    if (proxy.id == header.object) {
                        break deserializeEvent(
                            Event,
                            header,
                            proxy.interface,
                            buf[0..msg_len],
                            conn,
                        );
                    }
                } else continue;

                switch (ev) {
                    .wl_display => |disp_ev| try self.handleDisplayEvent(disp_ev),
                    else => return ev,
                }
            }
        }

        fn handleDisplayEvent(self: *Self, ev: anytype) !void {
            switch (ev) {
                .@"error" => |err| {
                    const proxy = for (self.proxies.items) |proxy| {
                        if (proxy.id == err.object_id) {
                            break proxy;
                        }
                    } else Proxy{ .id = err.object_id, .interface = "object" };
                    return handleDisplayError(proxy, err.code, err.message);
                },
                .delete_id => |id| {
                    self.delObject(id.id);
                    try self.ida.free(id.id);
                },
            }
        }

        fn handleDisplayError(
            proxy: Proxy,
            code: u32,
            message: [:0]const u8,
        ) error{ProtocolError} {
            std.log.err("Protocol error: {s}(id {d}): code: {d}\n\t{s}.", .{
                proxy.interface,
                proxy.id,
                code,
                message,
            });
            return error.ProtocolError;
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
    // This is arbitrary, but works for now.
    @setEvalBranchQuota(10000);

    const ti = @typeInfo(Event).@"union";
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

                // Deserialize the event packet and create an *Event struct
                // (e.g. wayland.Display.DeleteIdEvent)
                var event: sub_field.type = wire.deserializeEvent(sub_field.type, bytes, &fds);

                // Since the target object is derived from the header,
                // rather than the message signature, it is set after deserializing
                const object_self_field = std.meta.fields(@TypeOf(event))[0];
                @field(event, object_self_field.name) = @enumFromInt(header.object);

                // Initialize the interface-level event struct (e.g. protocol.Event.wl_display)
                const interface_event = @unionInit(field.type, sub_field.name, event);

                // Initialize the top-level event (protocol.Event).
                const global_event = @unionInit(Event, field.name, interface_event);

                return global_event;
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
