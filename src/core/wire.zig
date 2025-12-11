//! Utility functions and types for serializing and deserializing messages according to
//! the Wayland wire protocol (see https://wayland.freedesktop.org/docs/html/ch04.html).

/// Two-word message header containing target object id, message opcode, and length in bytes,
/// including the header.
pub const Header = switch (@import("builtin").target.cpu.arch.endian()) {
    .little => extern struct {
        object: u32,
        opcode: u16,
        length: u16,
    },
    .big => extern struct {
        object: u32,
        length: u16,
        opcode: u16,
    },
};

/// A null-terminated string with undefined byte encoding,
/// prefixed by its length including the null terminator.
pub const String = struct {
    data: [:0]const u8,
    padded_len: usize,

    pub fn init(data: [:0]const u8) String {
        return .{
            .data = data,
            .padded_len = roundup4(data.len + 1),
        };
    }
};

/// A blob of data prefixed by its length
pub const Array = struct {
    data: []const u8,
    padded_len: usize,

    pub fn init(data: []const u8) Array {
        return .{
            .data = data,
            .padded_len = roundup4(data.len),
        };
    }
};

/// A new id argument whose interface and version cannot be determined from the xml,
/// and therefore must be prefixed by this information.
pub const GenericNewId = struct {
    interface: String,
    version: u32,
    new_id: u32,

    pub fn init(comptime T: type, version: T.Version, new_id: u32) GenericNewId {
        return .{
            .interface = .init(T.interface),
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

/// Serialize `args` to `buffer`, encoding `object` and `opcode` in the header.
pub fn serializeArgs(
    buffer: []u8,
    object: u32,
    opcode: u16,
    args: anytype,
) u16 {
    const length = calculateArgsLength(args);
    const head = Header{
        .object = object,
        .opcode = opcode,
        .length = length,
    };
    @memcpy(buffer[0..@sizeOf(Header)], std.mem.asBytes(&head));

    var index: usize = @sizeOf(Header);
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |f|
        index += serializeArg(buffer[index..], @field(args, f.name));

    return length;
}

pub fn deserializeEventType(
    comptime T: type,
    bytes: []const u8,
    fds: []const std.posix.fd_t,
) T {
    const signature = T._signature;
    var event: T = undefined;
    var index: usize = 0;
    var fd_index: usize = 0;

    switch (@typeInfo(T)) {
        .@"struct" => |s| inline for (s.fields[1..], 0..) |field, sig_index| {
            const sig_byte = signature[sig_index];
            if (sig_byte != 'd') {
                const val, const size = deserializeArg(field.type, sig_byte, bytes[index..]);
                @field(event, field.name) = val;
                index += size;
            } else {
                @field(event, field.name) = fds[fd_index];
                fd_index += 1;
            }
        },
        else => @compileError("Expected args to be a struct or tuple."),
    }

    return event;
}

const std = @import("std");
const Fixed = @import("Fixed.zig");

fn calculateArgsLength(args: anytype) u16 {
    var length: u16 = 8;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        switch (field.type) {
            String, Array => length += @intCast(@field(args, field.name).padded_len + 4),
            GenericNewId => length += @intCast((@field(args, field.name).interface.padded_len + 12)),
            ?String => length += if (@field(args, field.name) == null) 4 else @intCast(@field(args, field.name).?.padded_len + 4),
            else => length += 4,
        }
    }
    return length;
}

fn serializeArg(buffer: []u8, arg: anytype) usize {
    const T = @TypeOf(arg);
    return switch (@typeInfo(T)) {
        .int => switch (T) {
            i32 => serializeInt(buffer, arg),
            u32 => serializeUint(buffer, arg),
            else => @compileError("Expected int arg to be 32 bits."),
        },
        .@"struct" => switch (T) {
            String => serializeString(buffer, arg),
            Array => serializeArray(buffer, arg),
            GenericNewId => serializeGenericNewId(buffer, arg),
            Fixed => serializeFixed(buffer, arg),
            else => serializeUint(buffer, @bitCast(arg)),
        },
        .@"enum" => |e| switch (e.tag_type) {
            i32 => serializeInt(buffer, @intFromEnum(arg)),
            u32 => serializeUint(buffer, @intFromEnum(arg)),
            else => @compileError("Unexpected enum tag type."),
        },
        .optional => |o| switch (o.child) {
            u32 => serializeUint(buffer, arg),
            String => serializeString(buffer, arg),
            else => @compileError("Expected optional to be either an object or String."),
        },
        else => @compileError(std.fmt.comptimePrint("Unexpected arg type: {s}", .{@typeName(T)})),
    };
}

fn serializeInt(buffer: []u8, int: i32) usize {
    std.mem.bytesAsValue(i32, buffer[0..@sizeOf(i32)]).* = int;
    return @sizeOf(i32);
}

fn serializeUint(buffer: []u8, uint: ?u32) usize {
    std.mem.bytesAsValue(u32, buffer[0..@sizeOf(u32)]).* = uint orelse 0;
    return @sizeOf(u32);
}

fn serializeFixed(buffer: []u8, fixed: Fixed) usize {
    return serializeInt(buffer, fixed.data);
}

fn serializeString(buffer: []u8, string: ?String) usize {
    if (string) |s| {
        const written = serializeUint(buffer, @intCast(s.data.len + 1));
        @memcpy(buffer[written .. written + s.data.len], s.data);
        buffer[written + s.data.len] = 0;
        return written + s.padded_len;
    } else {
        return serializeUint(buffer, 0);
    }
}

fn serializeGenericNewId(buffer: []u8, new_id: GenericNewId) usize {
    var written = serializeString(buffer, new_id.interface);
    written += serializeUint(buffer[written..], new_id.version);
    return written + serializeUint(buffer[written..], new_id.new_id);
}

fn serializeArray(buffer: []u8, array: Array) usize {
    const written = serializeUint(buffer, @intCast(array.data.len));
    @memcpy(buffer[written .. written + array.data.len], array.data);
    return written + array.padded_len;
}

fn deserializeArg(comptime T: type, comptime sig_byte: u8, bytes: []const u8) struct { T, usize } {
    switch (@typeInfo(T)) {
        .int => {
            comptime std.debug.assert(sig_byte == 'i' or sig_byte == 'u');
            const val = std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
            return .{ val, @sizeOf(T) };
        },
        .@"struct" => switch (sig_byte) {
            'f' => {
                const val = Fixed{ .data = std.mem.bytesToValue(i32, bytes[0..@sizeOf(i32)]) };
                return .{ val, @sizeOf(i32) };
            },
            'u' => {
                const val = @as(T, @bitCast(std.mem.bytesToValue(u32, bytes[0..@sizeOf(u32)])));
                return .{ val, @sizeOf(u32) };
            },
            else => unreachable,
        },
        .@"enum" => |e| {
            comptime std.debug.assert(sig_byte == 'i' or sig_byte == 'u' or sig_byte == 'o' or sig_byte == 'n');
            const val: T = @enumFromInt(std.mem.bytesToValue(e.tag_type, bytes[0..@sizeOf(e.tag_type)]));
            return .{ val, @sizeOf(e.tag_type) };
        },
        .pointer => |p| {
            const len = std.mem.bytesToValue(u32, bytes[0..@sizeOf(u32)]);
            if (p.sentinel_ptr != null) {
                const val: [:0]const u8 = @ptrCast(bytes[4 .. len + 3]);
                return .{ val, roundup4(len) + @sizeOf(u32) };
            } else {
                const val: []const u8 = bytes[4 .. len + 4];
                return .{ val, roundup4(len) + @sizeOf(u32) };
            }
        },
        .optional => |o| {
            switch (@typeInfo(o.child)) {
                .@"enum" => |e| {
                    comptime std.debug.assert(sig_byte == 'i' or sig_byte == 'u' or sig_byte == 'o' or sig_byte == 'n');
                    // TODO: handle new ids
                    const val: T = @enumFromInt(std.mem.bytesToValue(e.tag_type, bytes[0..@sizeOf(e.tag_type)]));
                    return .{ val, @sizeOf(e.tag_type) };
                },
                .pointer => |p| {
                    const len = std.mem.bytesToValue(u32, bytes[0..@sizeOf(u32)]);
                    if (p.sentinel_ptr != null) {
                        const val: [:0]const u8 = @ptrCast(bytes[0 .. len - 1]);
                        return .{ val, len + @sizeOf(u32) };
                    } else {
                        const val: []const u8 = bytes[0..len];
                        return .{ val, len + @sizeOf(u32) };
                    }
                },
                else => {
                    @compileError(std.fmt.comptimePrint("Unexpected optional type: {s}", .{@typeName(T)}));
                },
            }
        },
        else => {
            @compileError(std.fmt.comptimePrint("Unexpected type: {s}", .{@typeName(T)}));
        },
    }
}

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
