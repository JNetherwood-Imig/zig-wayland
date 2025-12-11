const std = @import("std");

const cmsg = @import("cmsg.zig");

const Fd = @import("Fd.zig");
const Fixed = @import("Fixed.zig");

// Message maximum size enforced by libwayland.
// It will terminate the connection of any client which attempts to pass a larger buffer.
const message_max_length: usize = 4096;

// Libwayland also enforces a maximum number of wl_closure args.
// This largely doesn't matter for this API, but it does mean we can safely cap the amount
// of allowed file descriptors here to save on memory when serializing.
const message_max_fds: usize = 20;

/// Wayland wire message header
pub const Header = extern struct {
    object: u32,
    opcode: u16,
    length: u16,
};

/// Wayland wire string representation, which is null-terminated and padded to 32 bits
pub const String = struct {
    padded_len: usize,
    data: [:0]const u8,

    /// Init wayland string from null-terminated byte slice
    pub fn init(data: [:0]const u8) String {
        return String{
            .padded_len = roundup4(data.len + 1),
            .data = data,
        };
    }
};

/// Wayland wire array representation, which is padded to 32 bits
pub const Array = struct {
    padded_len: usize,
    data: []const u8,

    /// Init wayland array from byte slice
    pub fn init(data: []const u8) Array {
        return Array{
            .padded_len = roundup4(data.len),
            .data = data,
        };
    }
};

/// Wayland wire new id with an interface that cannot be inferred from the xml
pub const GenericNewId = struct {
    interface: String,
    version: u32,
    new_id: u32,
};

/// A wayland wire message, which holds the maximum message size so no dynamic allocations are necessary
pub const Message = struct {
    buf: [message_max_length]u8 align(@alignOf(Header)),
    buf_index: usize = @sizeOf(Header),
    have_ancillary: bool = false,
    ancillary: [cmsg.space(message_max_fds)]u8,
    ancillary_index: usize,

    pub const empty = std.mem.zeroInit(Message, .{});

    pub fn init(object: u32, opcode: u16, args: anytype) !Message {
        var self: Message = .empty;

        switch (@typeInfo(@TypeOf(args))) {
            .@"struct" => |s| inline for (s.fields) |f| try self.serializeArg(@field(args, f.name)),
            else => @compileError("Expected args to be a struct or tuple."),
        }

        const head = Header{
            .object = object,
            .opcode = opcode,
            .length = @intCast(self.buf_index),
        };
        @memcpy(self.buf[0..@sizeOf(Header)], std.mem.asBytes(&head));

        const control = cmsg.Header{
            .cmsg_len = cmsg.length(self.ancillary_index),
        };
        @memcpy(self.ancillary[0..cmsg.length(0)], std.mem.asBytes(&control));

        return self;
    }

    pub fn header(self: *Message) *Header {
        return @ptrCast(&self.buf);
    }

    pub fn dataConst(self: *Message) []const u8 {
        return self.buf[0..self.buf_index];
    }

    pub fn dataPtrConst(self: *const Message) [*]const u8 {
        return &self.buf;
    }

    pub fn dataLen(self: *const Message) usize {
        return self.buf_index;
    }

    pub fn dataIovecConst(self: *const Message) std.posix.iovec_const {
        const slice = self.buf[0..];
        return .{ .base = slice.ptr, .len = slice.len };
    }

    pub fn dataIovec(self: *Message) std.posix.iovec {
        const slice = self.buf[0..];
        return .{ .base = slice.ptr, .len = slice.len };
    }

    pub fn ancillaryData(self: *Message) ?*anyopaque {
        return if (self.have_ancillary)
            @as(*anyopaque, @ptrCast(&self.ancillary))
        else
            null;
    }

    pub fn ancillaryDataConst(self: *const Message) ?*const anyopaque {
        return if (self.have_ancillary)
            @as(*const anyopaque, @ptrCast(&self.ancillary))
        else
            null;
    }

    pub fn ancillaryDataLen(self: *const Message) usize {
        return if (self.have_ancillary)
            cmsg.length(self.ancillary_index)
        else
            0;
    }

    fn serializeArg(self: *Message, arg: anytype) !void {
        const T = @TypeOf(arg);
        try switch (@typeInfo(T)) {
            .int => switch (T) {
                i32 => self.serializeInt(arg),
                u32 => self.serializeUint(arg),
                else => @compileError("Expected int arg to be 32 bits."),
            },
            .@"struct" => switch (T) {
                Fd => self.serializeFd(arg),
                String => self.serializeString(arg),
                Array => self.serializeArray(arg),
                GenericNewId => self.serializeGenericNewId(arg),
                Fixed => self.serializeFixed(arg),
                else => @compileError("Unexpected struct arg type."),
            },
            .optional => |o| switch (o.child) {
                String => self.serializeString(arg),
                else => @compileError("Expected optional to be either a Proxy or String."),
            },
            else => @compileError(std.fmt.comptimePrint("Unexpected arg type: {s}", .{@typeName(T)})),
        };
    }

    fn serializeInt(self: *Message, int: i32) !void {
        if (self.buf_index + 4 >= self.buf.len) return error.MessageTooLong;
        std.mem.bytesAsValue(i32, self.buf[self.buf_index .. self.buf_index + 4]).* = int;
        self.buf_index += 4;
    }

    fn serializeUint(self: *Message, uint: u32) !void {
        if (self.buf_index + 4 >= self.buf.len) return error.MessageTooLong;
        std.mem.bytesAsValue(u32, self.buf[self.buf_index .. self.buf_index + 4]).* = uint;
        self.buf_index += 4;
    }

    fn serializeFixed(self: *Message, fixed: Fixed) !void {
        try self.serializeInt(@bitCast(fixed));
    }

    fn serializeString(self: *Message, string: ?String) !void {
        if (string) |s| {
            try self.serializeUint(@intCast(s.padded_len));
            if (self.buf_index + s.padded_len >= self.buf.len) return error.MessageTooLong;
            @memcpy(self.buf[self.buf_index .. self.buf_index + s.data.len], s.data);
            self.buf[self.buf_index + s.data.len] = 0;
            self.buf_index += s.padded_len;
        } else {
            try self.serializeUint(0);
        }
    }

    fn serializeGenericNewId(self: *Message, new_id: GenericNewId) !void {
        try self.serializeString(new_id.interface);
        try self.serializeUint(new_id.version);
        try self.serializeUint(new_id.new_id);
    }

    fn serializeArray(self: *Message, array: Array) !void {
        try self.serializeUint(@intCast(array.padded_len));
        @memcpy(self.buf[self.buf_index .. self.buf_index + array.data.len], array.data);
        self.buf_index += array.padded_len;
    }

    fn serializeFd(self: *Message, fd: Fd) !void {
        self.have_ancillary = true;
        if (self.ancillary_index >= message_max_fds) return error.TooManyFds;
        const idx = cmsg.length(0) + self.ancillary_index * @sizeOf(Fd);
        std.mem.bytesAsValue(i32, self.ancillary[idx .. idx + 4]).* = fd.raw;
        self.ancillary_index += 1;
    }
};

fn roundup4(value: anytype) @TypeOf(value) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int => (value + 3) & ~@as(T, 3),
        else => @compileError("Unsupported type (roundup4)."),
    };
}

test "roundup4" {
    try std.testing.expectEqual(0, roundup4(@as(usize, 0)));
    try std.testing.expectEqual(4, roundup4(@as(usize, 4)));
    try std.testing.expectEqual(4, roundup4(@as(usize, 3)));
    try std.testing.expectEqual(24, roundup4(@as(u18, 21)));
    try std.testing.expectEqual(100, roundup4(@as(u16, 97)));
    try std.testing.expectEqual(1024, roundup4(@as(u32, 1022)));
}
