//! Utility functions and types for serializing and deserializing messages according to
//! the Wayland wire protocol (see https://wayland.freedesktop.org/docs/html/ch04.html).

const std = @import("std");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const Fixed = @import("Fixed.zig");

pub const libwayland_max_message_length = 4096;
pub const libwayland_max_message_args = 20;

/// Two-word message header containing target object id, message opcode, and length in bytes,
/// including the header.
pub const Header = switch (native_endian) {
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

    /// Initialize a string and calculate its padded length for serialization.
    pub fn init(data: [:0]const u8) String {
        return .{
            .data = data,
            .padded_len = roundup4(data.len + 1),
        };
    }

    /// Initialize an optional string and calculate its padded length for serialization.
    /// Returns null if data is null.
    /// This function serves the purpose of simplifying possible argument types
    /// when working with optional arguments.
    pub fn initNullable(data: ?[:0]const u8) ?String {
        return if (data) |d| String{
            .data = d,
            .padded_len = roundup4(d.len + 1),
        } else null;
    }
};

/// A blob of data prefixed by its length.
pub const Array = struct {
    data: []const u8,
    padded_len: usize,

    /// Initialize an array and calculate its padded length for serialization.
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
    interface: [:0]const u8,
    version: u32,
    new_id: u32,

    /// Initialize a generic new id from the params that will be present in codegen.
    pub fn init(comptime T: type, version: T.Version, new_id: u32) GenericNewId {
        return .{
            .interface = T.interface,
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

/// Serialize `args` to `buffer`, encoding `object` and `opcode` in the header.
pub fn serializeMessage(
    buffer: []u8,
    object: u32,
    opcode: u16,
    args: anytype,
) usize {
    const length = calculateArgsLength(args);
    std.mem.bytesAsValue(Header, buffer[0..@sizeOf(Header)]).* = .{
        .object = object,
        .opcode = opcode,
        .length = length,
    };

    var index: usize = @sizeOf(Header);
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |f|
        index += serializeArg(buffer[index..], @field(args, f.name));

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
    var written = serializeString(buffer, String.init(new_id.interface));
    written += serializeUint(buffer[written..], new_id.version);
    return written + serializeUint(buffer[written..], new_id.new_id);
}

fn serializeArray(buffer: []u8, array: Array) usize {
    const written = serializeUint(buffer, @intCast(array.data.len));
    @memcpy(buffer[written .. written + array.data.len], array.data);
    return written + array.padded_len;
}

fn calculateArgsLength(args: anytype) u16 {
    var length: u16 = 8;
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| switch (field.type) {
        String, Array => length += @intCast(@field(args, field.name).padded_len + 4),
        GenericNewId => length += @intCast((roundup4(@field(args, field.name).interface.len) + 12)),
        ?String => length += if (@field(args, field.name)) |s| @intCast(s.padded_len + 4) else 4,
        else => length += 4,
    };
    return length;
}

/// Deserialize `bytes` and `fds` into a `T`.
pub fn deserializeMessage(
    comptime T: type,
    bytes: []const u8,
    fds: []const std.posix.fd_t,
) T {
    const signature = T._signature;
    var event: T = undefined;
    var index: usize = 0;
    var fd_index: usize = 0;

    switch (@typeInfo(T)) {
        .@"struct" => |s| inline for (s.fields[1..], signature) |field, sig_byte| {
            if (sig_byte == 'd') { // field is an fd
                @field(event, field.name) = fds[fd_index];
                fd_index += 1;
                continue;
            }

            const val, const size = deserializeField(field.type, bytes[index..]);
            @field(event, field.name) = val;
            index += size;
        },
        else => @compileError("Expected args to be a struct or tuple."),
    }

    return event;
}

/// Deserialize a single field of type `T` from `data`
/// Returns the element, `T`, and the bytes consumed
fn deserializeField(comptime T: type, data: []const u8) struct { T, usize } {
    return switch (@typeInfo(T)) {
        .int => switch (T) {
            i32 => deserializeInt(data),
            u32 => deserializeUint(data),
            else => @compileError("Expected int arg to be 32 bits."),
        },
        .@"enum" => deserializeEnum(T, data),
        .@"struct" => switch (T) {
            GenericNewId => deserializeGenericNewId(data),
            Fixed => deserializeFixed(data),
            else => deserializeBitfield(T, data),
        },
        .pointer => switch (T) {
            [:0]const u8 => deserializeString(data),
            []const u8 => deserializeArray(data),
            else => @compileError("Invalid pointer type in incoming message."),
        },
        .optional => |o| switch (o.child) {
            [:0]const u8 => deserializeOptionalString(data),
            else => deserializeOptionalObject(o.child, data),
        },
        else => @compileError(std.fmt.comptimePrint("Unexpected arg type: {s}", .{@typeName(T)})),
    };
}

fn deserializeInt(data: []const u8) struct { i32, usize } {
    return .{ std.mem.bytesToValue(i32, data[0..4]), 4 };
}

fn deserializeUint(data: []const u8) struct { u32, usize } {
    return .{ std.mem.bytesToValue(u32, data[0..4]), 4 };
}

fn deserializeFixed(data: []const u8) struct { Fixed, usize } {
    const raw, _ = deserializeInt(data);
    return .{ .{ .data = raw }, 4 };
}

fn deserializeArray(data: []const u8) struct { []const u8, usize } {
    const len, _ = deserializeUint(data);
    return .{ data[4..][0..len], 4 + roundup4(len) };
}

fn deserializeString(data: []const u8) struct { [:0]const u8, usize } {
    const len, _ = deserializeUint(data);
    return .{ @ptrCast(data[4..][0 .. len - 1]), 4 + roundup4(len) };
}

fn deserializeOptionalString(data: []const u8) struct { ?[:0]const u8, usize } {
    const len, _ = deserializeUint(data);
    if (len == 0) return .{ null, 4 };

    return .{ @ptrCast(data[4..][0 .. len - 1]), 4 + roundup4(len) };
}

fn deserializeGenericNewId(data: []const u8) struct { GenericNewId, usize } {
    const interface, const len = deserializeString(data);
    const version, _ = deserializeUint(data[len..]);
    const new_id, _ = deserializeUint(data[len..][4..]);

    return .{
        .{
            .interface = interface,
            .version = version,
            .new_id = new_id,
        },
        len + 8,
    };
}

fn deserializeBitfield(comptime T: type, data: []const u8) struct { T, usize } {
    const val, const len = deserializeUint(data);
    return .{ @bitCast(val), len };
}

fn deserializeEnum(comptime T: type, data: []const u8) struct { T, usize } {
    const val, const len = switch (@typeInfo(T).@"enum".tag_type) {
        i32 => deserializeInt(data),
        u32 => deserializeUint(data),
        else => @compileError("Unexpected enum tag type."),
    };
    return .{ @enumFromInt(val), len };
}

fn deserializeOptionalObject(comptime T: type, data: []const u8) struct { ?T, usize } {
    const val, const len = deserializeUint(data);
    if (val == 0) return .{ null, len };
    return .{ @enumFromInt(val), len };
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
