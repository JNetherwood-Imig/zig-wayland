//! Utility functions and types for serializing and deserializing messages according to
//! the [Wayland wire protocol](https://wayland.freedesktop.org/docs/html/ch04.html).

const std = @import("std");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const Fixed = @import("Fixed.zig");

pub const libwayland_max_message_size = 4096;
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

/// When the type of a `new_id` argument cannot be inferred from the xml, it must be prefixed
/// with the interface, a string, and the version, a u32.
pub const GenericNewId = struct {
    interface: [:0]const u8,
    version: u32,
    new_id: u32,

    /// Initialize a generic new id from the parameters that will be present in codegen.
    pub fn init(comptime T: type, version: T.Version, new_id: u32) GenericNewId {
        return .{
            .interface = T.interface,
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

/// Serialize `args` to `buffer`, encoding `object` and `opcode` in the header.
/// Returns the length of the serialized message, including the header.
pub fn serializeMessage(buffer: []u8, object: u32, opcode: u16, args: anytype) usize {
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

/// Serialize a single argument, `arg`, to `buffer`.
/// Returns the length of `arg` as serialized.
fn serializeArg(buffer: []u8, arg: anytype) usize {
    const T = @TypeOf(arg);
    return switch (@typeInfo(T)) {
        .int => switch (T) {
            i32 => serializeInt(buffer, arg),
            u32 => serializeUint(buffer, arg),
            else => @compileError("Unexpected int type."),
        },
        .@"struct" => switch (T) {
            Fixed => serializeFixed(buffer, arg),
            GenericNewId => serializeGenericNewId(buffer, arg),
            else => serializeUint(buffer, @bitCast(arg)),
        },
        .@"enum" => |e| switch (e.tag_type) {
            i32 => serializeInt(buffer, @intFromEnum(arg)),
            u32 => serializeUint(buffer, @intFromEnum(arg)),
            else => @compileError("Unexpected enum tag type."),
        },
        .pointer => switch (T) {
            []const u8 => serializeArray(buffer, arg),
            [:0]const u8 => serializeString(buffer, arg),
            else => @compileError("Unexpected pointer type."),
        },
        .optional => |o| switch (o.child) {
            [:0]const u8 => serializeOptionalString(buffer, arg),
            else => serializeUint(buffer, if (arg) |obj| obj.getId() else 0),
        },
        else => @compileError(std.fmt.comptimePrint("Unexpected arg type: {s}", .{@typeName(T)})),
    };
}

/// Writes `int` to the beginning of `buffer` and returns `@sizeOf(i32)`.
fn serializeInt(buffer: []u8, int: i32) usize {
    std.mem.bytesAsValue(i32, buffer[0..@sizeOf(i32)]).* = int;
    return @sizeOf(i32);
}

test "serialize int" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeInt(&buf, -65536));
    try std.testing.expectEqual(-65536, std.mem.bytesToValue(i32, &buf));
}

/// Writes `uint` to the beginning of `buffer` and returns `@sizeOf(u32)`.
fn serializeUint(buffer: []u8, uint: u32) usize {
    std.mem.bytesAsValue(u32, buffer[0..@sizeOf(u32)]).* = uint;
    return @sizeOf(u32);
}

test "serialize uint" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeUint(&buf, 65536));
    try std.testing.expectEqual(65536, std.mem.bytesToValue(u32, &buf));
}

/// Serializes a nullable object as its id, or zero if null. Returns @sizeOf(u32).
fn serializeOptionalObject(buffer: []u8, object: anytype) usize {
    return serializeUint(buffer, if (object) |o| o.getId() else 0);
}

test "serialize optional object" {
    const Test = enum(u32) {
        invalid = 0,
        _,
        const interface = "hello, world!";
        const Version = enum(u32) { v1 = 1, v2 = 2 };

        fn getId(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };

    const obj1: ?Test = @enumFromInt(3);
    const obj2: ?Test = null;

    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeOptionalObject(&buf, obj1));
    try std.testing.expectEqual(3, std.mem.bytesToValue(u32, &buf));
    try std.testing.expectEqual(4, serializeOptionalObject(&buf, obj2));
    try std.testing.expectEqual(Test.invalid, std.mem.bytesToValue(Test, &buf));
}

/// Writes the backing i32 of `fixed` to the beginning of `buffer` and returns `@sizeOf(i32)`.
fn serializeFixed(buffer: []u8, fixed: Fixed) usize {
    return serializeInt(buffer, fixed.data);
}

test "serialize fixed" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeFixed(&buf, .from(2.1)));
    try std.testing.expectApproxEqAbs(2.1, std.mem.bytesToValue(Fixed, &buf).to(f64), 0.01);
}

/// Writes the length of `string` including the null terminator followed by the contents of `string`
/// to the beginning of the buffer.
/// Returns @sizeOf(u32) plus the serialized length rounded up to
/// the nearest multiple of 4 bytes.
/// For a string of length 12, returns 4 + roundup4(12 + 1) --> 4 + roundup4(13) --> 4 + 16 --> 20.
fn serializeString(buffer: []u8, string: [:0]const u8) usize {
    const written = serializeUint(buffer, @intCast(string.len + 1));
    @memcpy(buffer[written..][0..string.len], string);
    buffer[written + string.len] = 0;
    return written + roundup4(string.len + 1);
}

test "serialize string" {
    const message = "hello, world!";
    var buf: [20]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeString(&buf, message));
    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(message.len + 1, len);
    try std.testing.expectEqualSlices(u8, message, buf[4..][0..message.len]);
}

/// Same as `serializeString`, except if `string` is null,
/// a zero is written to signify no content and @sizeOf(u32) is returned.
fn serializeOptionalString(buffer: []u8, string: ?[:0]const u8) usize {
    return if (string) |s|
        serializeString(buffer, s)
    else
        serializeUint(buffer, 0);
}

test "serialize optional string" {
    const message = "hello, world!";
    var buf: [20]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeOptionalString(&buf, message));
    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(message.len + 1, len);
    try std.testing.expectEqualSlices(u8, message, buf[4..][0..message.len]);

    try std.testing.expectEqual(4, serializeOptionalString(&buf, null));
    const len2 = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(0, len2);
}

/// Writes the interface of `new_id` as a nonnull string, followed by version as a uint,
/// followed by the id itself, also as a u32.
/// Returns the serialized length of interface plus `2 * @sizeOf(u32)`.
fn serializeGenericNewId(buffer: []u8, new_id: GenericNewId) usize {
    var written = serializeString(buffer, new_id.interface);
    written += serializeUint(buffer[written..], new_id.version);
    return written + serializeUint(buffer[written..], new_id.new_id);
}

test "serialize generic new id" {
    const Test = enum(u32) {
        invalid = 0,
        _,
        const interface = "hello, world!";
        const Version = enum(u32) { v1 = 1, v2 = 2 };
    };

    var buf: [28]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeGenericNewId(&buf, .init(Test, .v2, 1)));

    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(Test.interface.len + 1, len);
    try std.testing.expectEqualSlices(u8, Test.interface, buf[4..][0..Test.interface.len]);
    try std.testing.expectEqual(2, std.mem.bytesToValue(u32, buf[20..24]));
    try std.testing.expectEqual(1, std.mem.bytesToValue(u32, buf[24..28]));
}

/// Writes the length of `array` followed by the bytes of `array` to the beginning of the buffer.
/// Returns @sizeOf(u32) plus the serialized length rounded up to the nearest multiple of 4 bytes.
/// For an array of length 12, returns 4 + roundup4(12) --> 4 + roundup4(12) --> 4 + 12 --> 16.
fn serializeArray(buffer: []u8, array: []const u8) usize {
    const written = serializeUint(buffer, @intCast(array.len));
    @memcpy(buffer[written..][0..array.len], array);
    return written + roundup4(array.len);
}

test "serialize array" {
    const arr = [_]u8{ 0, 1, 2, 3, 4, 5, 6 };
    var buf: [12]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeArray(&buf, &arr));
    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(arr.len, len);
    try std.testing.expectEqualSlices(u8, &arr, buf[4..][0..arr.len]);
}

/// Returns the sum of the serialized lengths of all fields of `args`, plus @sizeOf(Header).
fn calculateArgsLength(args: anytype) u16 {
    var length: u16 = @intCast(@sizeOf(Header));
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        const f = @field(args, field.name);
        length += switch (field.type) {
            []const u8 => @intCast(roundup4(f.len) + 4),
            [:0]const u8 => @intCast(roundup4(f.len + 1) + 4),
            ?[:0]const u8 => if (f) |s| @intCast(roundup4(s.len + 1) + 4) else 4,
            GenericNewId => @intCast(roundup4(f.interface.len) + 12),
            else => 4,
        };
    }
    return length;
}

test "calculate args length" {
    // Start with 8 bytes for header
    const args = .{
        @as(i32, -1), // + 4 = 12
        @as(u32, 2), // + 4 = 16
        Fixed.from(12.34), // + 4 = 20
        @as(?[:0]const u8, null), // + 4 = 24
        @as([]const u8, &.{ 0, 1, 2, 3, 4 }), // + 4 + 8 = 36
    };

    try std.testing.expectEqual(36, calculateArgsLength(args));
}

/// Constructs a `T`  from `bytes` and `fds`. Expects `t` to have been generated by the scanner;
pub fn deserializeMessage(comptime T: type, bytes: []const u8, fds: []const std.posix.fd_t) T {
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
            else => @compileError("Unexpected int type."),
        },
        .@"struct" => switch (T) {
            GenericNewId => deserializeGenericNewId(data),
            Fixed => deserializeFixed(data),
            else => deserializeBitfield(T, data),
        },
        .pointer => switch (T) {
            []const u8 => deserializeArray(data),
            [:0]const u8 => deserializeString(data),
            else => @compileError("Invalid pointer type in incoming message."),
        },
        .optional => |o| switch (o.child) {
            [:0]const u8 => deserializeOptionalString(data),
            else => deserializeOptionalObject(o.child, data),
        },
        .@"enum" => deserializeEnum(T, data),
        else => @compileError(std.fmt.comptimePrint("Unexpected arg type: {s}", .{@typeName(T)})),
    };
}

/// Reads an i32 from the beginning of `data`. Returns the i32 alongside its size.
fn deserializeInt(data: []const u8) struct { i32, usize } {
    return .{ std.mem.bytesToValue(i32, data[0..4]), 4 };
}

/// Reads an u32 from the beginning of `data`. Returns the u32 alongside its size.
fn deserializeUint(data: []const u8) struct { u32, usize } {
    return .{ std.mem.bytesToValue(u32, data[0..4]), 4 };
}

/// Reads an i32 from the beginning of `data` and initializes a `Fixed` with the i32
/// as the backing data. Returns the resulting `Fixed` alongside the consumed length,
/// which is the size of its backing i32.
fn deserializeFixed(data: []const u8) struct { Fixed, usize } {
    const raw, _ = deserializeInt(data);
    return .{ .{ .data = raw }, 4 };
}

/// Reads a u32 describing the array length, then the contents of the array, from the beginning
/// of `data`. Returns the slice of bytes, alongside the consumed length,
/// which is the size of a u32 plus the array length, rounded up to 4 bytes.
fn deserializeArray(data: []const u8) struct { []const u8, usize } {
    const len, _ = deserializeUint(data);
    return .{ data[4..][0..len], 4 + roundup4(len) };
}

/// Reads a nonzero u32 describing the string length, including its null terminator,
/// then the contents of the string, from the beginning of `data`.
/// Returns the string, alongside the consumed length,
/// which is the size of a u32 plus the string length minus 1, rounded up to 4 bytes.
fn deserializeString(data: []const u8) struct { [:0]const u8, usize } {
    const len, _ = deserializeUint(data);
    return .{ @ptrCast(data[4..][0 .. len - 1]), 4 + roundup4(len) };
}

// Same as `deserializeString`, except if the string length is zero,
// in which case it returns null.
fn deserializeOptionalString(data: []const u8) struct { ?[:0]const u8, usize } {
    const len, _ = deserializeUint(data);
    if (len == 0) return .{ null, 4 };

    return .{ @ptrCast(data[4..][0 .. len - 1]), 4 + roundup4(len) };
}

/// Reads the object interface as a string, followed by version as u32, then finally the id itself
/// from the beginning of `data`.
/// Returns the `GenericNewId` alongside the bytes consumed, which is the sum of
/// the padded length of the interface and 3 * @sizeOf(u32).
fn deserializeGenericNewId(data: []const u8) struct { GenericNewId, usize } {
    const interface, const len = deserializeString(data);
    const version, _ = deserializeUint(data[len..]);
    const new_id, _ = deserializeUint(data[len..][4..]);

    return .{ .{
        .interface = interface,
        .version = version,
        .new_id = new_id,
    }, len + 8 };
}

/// Read a u32 from the beginning of `data` and bitcast it to `T`, which should be a
/// `packed struct(u32)` which stores a bitfield enum.
/// Returns a `T` alognside the bytes consumed, which is @sizeOf(u32).
fn deserializeBitfield(comptime T: type, data: []const u8) struct { T, usize } {
    const val, const len = deserializeUint(data);
    return .{ @bitCast(val), len };
}

/// Read a u32 or i32 from the beginning of `data` and cast it to `T`, which should be an enum
/// backed by either a u32 or i32.
/// Returns a `T` alongside the size of a 32 bit integer.
fn deserializeEnum(comptime T: type, data: []const u8) struct { T, usize } {
    const val, const len = switch (@typeInfo(T).@"enum".tag_type) {
        i32 => deserializeInt(data),
        u32 => deserializeUint(data),
        else => @compileError("Unexpected enum tag type."),
    };
    return .{ @enumFromInt(val), len };
}

/// Same as `deserializeEnum`, except returns a null value if the enum value is 0.
fn deserializeOptionalObject(comptime T: type, data: []const u8) struct { ?T, usize } {
    const obj, const len = deserializeEnum(T, data);
    if (obj == .invalid) return .{ null, len };
    return .{ obj, len };
}

/// Rounds an integer up to the nearest multiple of 4.
/// Used for calculating padding on the wire.
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
    try std.testing.expectEqual(1024, roundup4(@as(u32, 1021)));
    try std.testing.expectEqual(1024, roundup4(@as(u32, 1022)));
    try std.testing.expectEqual(1024, roundup4(@as(u32, 1023)));
    try std.testing.expectEqual(1024, roundup4(@as(u32, 1024)));
}
