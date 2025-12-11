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
    pub fn init(data: ?[:0]const u8) ?String {
        return if (data) |d| String{
            .padded_len = roundup4(d.len + 1),
            .data = d,
        } else null;
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

    pub fn init(comptime T: type, version: T.Version, new_id: u32) GenericNewId {
        return .{
            .interface = .init(T.interface),
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

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

    switch (@typeInfo(@TypeOf(args))) {
        .@"struct" => |s| inline for (s.fields) |f| {
            index += serializeArg(buffer[index..], @field(args, f.name));
        },
        else => @compileError("Expected args to be a struct or tuple."),
    }

    return length;
}

const std = @import("std");
const Fixed = @import("Fixed.zig");

fn calculateArgsLength(args: anytype) u16 {
    var length: u16 = 8;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        switch (field.type) {
            String, Array => length += @field(args, field.name).padded_len,
            GenericNewId => length += @intCast((@field(args, field.name).interface.padded_len + 8)),
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
            else => @compileError("Unexpected struct arg type."),
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
        const written = serializeUint(buffer, @intCast(s.padded_len));
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
    const written = serializeUint(buffer, @intCast(array.padded_len));
    @memcpy(buffer[written .. written + array.data.len], array.data);
    return written + array.padded_len;
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
