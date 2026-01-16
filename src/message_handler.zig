const std = @import("std");
const wire = @import("wire.zig");
const Connection = @import("Connection.zig");
const IdAllocator = @import("IdAllocator.zig");
const ProtocolSide = @import("wayland_core.zig").ProtocolSide;
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

        client_interfaces: []?[:0]const u8,
        server_interfaces: []?[:0]const u8,

        /// Initialize an unbounded message handler with an allocator and ititial capacity
        pub fn initCapacity(gpa: Allocator, initial_capacity: usize) Allocator.Error!Self {
            const client_interfaces = try gpa.alloc(?[:0]const u8, initial_capacity);
            for (client_interfaces) |*item| item.* = null;
            errdefer gpa.free(client_interfaces);

            const server_interfaces = try gpa.alloc(?[:0]const u8, initial_capacity);
            for (server_interfaces) |*item| item.* = null;

            return Self{
                .client_interfaces = client_interfaces,
                .server_interfaces = server_interfaces,
            };
        }

        /// Initialize a bounded message handler which does not invoke the heap.
        /// When initializing this way, always use addObjectBounded instead of addObject
        /// because an allocator cannot be used.
        pub fn initBuffered(client_buffer: []?[:0]const u8, server_buffer: []?[:0]const u8) Self {
            for (client_buffer) |*item| item.* = null;
            for (server_buffer) |*item| item.* = null;

            return .{
                .client_interfaces = client_buffer,
                .server_interfaces = server_buffer,
            };
        }

        /// Only to be used with `initCapacity`.
        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.client_interfaces);
            gpa.free(self.server_interfaces);
        }

        pub const AddObjectError = error{ InvalidObject, ObjectAlreadyExists, OutOfMemory };

        /// Add an object to an unbounded message handler.
        /// NOTE: Must have been initialized with `initCapacity`,
        /// it is invalid to use this function with `initBuffered`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObject(self: *Self, gpa: Allocator, object: anytype) AddObjectError!void {
            const id = object.getId();
            const interface = @TypeOf(object).interface;
            const side = try getSide(id);
            const idx = getIdx(id, side);

            try self.ensureCapacity(gpa, idx, side);
            try self.add(idx, interface, side);
        }

        /// Add an object to the message handler, failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        /// `object` must be a wayland object created either by a factory interface
        /// or by an `IdAllocator`
        pub fn addObjectBounded(self: *Self, object: anytype) AddObjectError!void {
            const id = object.getId();
            const interface = @TypeOf(object).interface;
            const side = try getSide(id);
            const idx = getIdx(id, side);
            const interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };

            if (idx >= interfaces.len) {
                @branchHint(.unlikely);
                return error.OutOfMemory;
            }
            try self.add(idx, interface, side);
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
            const side = try getSide(id);
            const idx = getIdx(id, side);
            try self.ensureCapacity(gpa, idx, side);
            try self.add(id, interface, side);
        }

        /// Add a raw id and associated interface to the message handler,
        /// failing if capacity is reached.
        /// This function is meant to be used with `initBuffered`,
        /// but is completely valid to use with `initCapacity`
        pub fn addRawBounded(self: *Self, id: u32, interface: [:0]const u8) AddObjectError!void {
            const side = try getSide(id);
            const idx = getIdx(id, side);
            const interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };
            if (idx >= interfaces.len) {
                @branchHint(.unlikely);
                return error.OutOfMemory;
            }
            try self.add(idx, interface, side);
        }

        pub const DelObjectError = error{InvalidObject};

        /// Remove an object from the handler.
        /// `object` can be either a wayland object from a factory interface
        /// or `IdAllocator` or a raw integer id.
        ///
        /// This function attempts to unregister the object by setting the interface at the index
        /// corresponding to the object id to `null`, and fails with `error.InvalidObject`
        /// when attempting to free an object that was never added.
        ///
        /// This error can safely be ignored if opting to not add objects without incoming messages.
        pub fn delObject(self: *Self, object: anytype) DelObjectError!void {
            const id = switch (@typeInfo(@TypeOf(object))) {
                .int => object,
                .@"enum" => object.getId(),
                else => @compileError("Unsupported type."),
            };
            const side = try getSide(id);
            const idx = getIdx(id, side);
            var interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };

            if (idx >= interfaces.len or interfaces[idx] == null) {
                @branchHint(.unlikely);
                log.err("Delete object: invalid object id: {d}.", .{id});
                return error.InvalidObject;
            }
            interfaces[idx] = null;
        }

        pub const GetMessageError = DeserializeError ||
            Connection.FlushError ||
            Connection.ReadIncomingError ||
            error{ InvalidObject, MessageTooLong };

        /// Try to get an message from the `connection`,
        /// immediately returning `null` if the buffers are empty and the socket is not readable.
        pub fn getNextMessage(
            self: *Self,
            io: std.Io,
            connection: *Connection,
        ) GetMessageError!?Message {
            return self.nextMessage(io, connection, .{ .duration = .{
                .raw = .zero,
                .clock = .awake,
            } });
        }

        /// Wait indefinately for an message to be received.
        pub fn waitNextMessage(
            self: *Self,
            io: std.Io,
            connection: *Connection,
            timeout: std.Io.Timeout,
        ) GetMessageError!Message {
            while (true) if (try self.nextMessage(io, connection, timeout)) |ev| return ev;
        }

        fn nextMessage(
            self: *Self,
            io: std.Io,
            conn: *Connection,
            timeout: std.Io.Timeout,
        ) GetMessageError!?Message {
            // Always start by flushing buffered messages
            conn.flush(io) catch |err| switch (err) {
                error.SocketUnconnected => {},
                else => |e| return e,
            };

            outer: while (true) {
                // Try to get a header, otherwise poll for messages,
                // returning null if polling times out
                const header = conn.peekHeader() orelse {
                    try conn.readIncoming(io, timeout);
                    continue :outer;
                };

                if (header.length > wire.libwayland_max_message_size)
                    return error.MessageTooLong;

                const message = conn.peek(header.length) orelse {
                    try conn.readIncoming(io, timeout);
                    continue :outer;
                };
                const body = message[@sizeOf(wire.Header)..];

                const interface = try self.getInterface(header.object);
                return try deserializeMessage(Message, header, interface, body, conn) orelse
                    continue :outer;
            }
        }

        fn ensureCapacity(
            self: *Self,
            gpa: Allocator,
            idx: usize,
            side: ProtocolSide,
        ) error{ InvalidObject, OutOfMemory }!void {
            var interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };

            if (idx > interfaces.len) return error.InvalidObject;

            if (idx == interfaces.len) {
                const new_capacity = interfaces.len * 2;
                const new_memory = gpa.remap(interfaces, new_capacity) orelse mem: {
                    const new_memory = try gpa.alloc(?[:0]const u8, new_capacity);
                    @memcpy(new_memory[0..interfaces.len], interfaces);
                    gpa.free(interfaces);
                    break :mem new_memory;
                };

                interfaces.ptr = new_memory.ptr;
                const old_len = interfaces.len;
                interfaces.len = new_memory.len;
                for (old_len..interfaces.len) |i|
                    interfaces[i] = null;
            }
        }

        fn add(
            self: *Self,
            idx: usize,
            interface: [:0]const u8,
            side: ProtocolSide,
        ) error{ObjectAlreadyExists}!void {
            const interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };

            if (interfaces[idx] != null) {
                @branchHint(.unlikely);
                return error.ObjectAlreadyExists;
            }
            interfaces[idx] = interface;
        }

        fn getSide(id: u32) error{InvalidObject}!ProtocolSide {
            return switch (id) {
                1, IdAllocator.client_min_id...IdAllocator.client_max_id => ProtocolSide.client,
                IdAllocator.server_min_id...IdAllocator.server_max_id => ProtocolSide.server,
                else => error.InvalidObject,
            };
        }

        fn getIdx(id: u32, side: ProtocolSide) usize {
            return switch (side) {
                .client => id - 1,
                .server => id - IdAllocator.server_min_id,
            };
        }

        pub fn getInterface(self: *Self, id: u32) error{InvalidObject}![:0]const u8 {
            const side = try getSide(id);
            const idx = getIdx(id, side);
            const interfaces = switch (side) {
                .client => self.client_interfaces,
                .server => self.server_interfaces,
            };
            return interfaces[idx] orelse error.InvalidObject;
        }
    };
}

const DeserializeError = wire.DeserializeError || error{InvalidOpcode};

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

    @panic("Interface not present in generated message union.");
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
