//! A 24.8 bit fixed-point number used in the Wayland wire format in place of floats.
const std = @import("std");

const Fixed = @This();

/// Backing data.
data: i32,

/// Create a `Fixed` storing `value`, which can be either an int, comptime int,
/// float, or comptime float.
pub fn from(value: anytype) Fixed {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => Fixed{ .data = @intCast(value * 256) },
        .float, .comptime_float => Fixed{ .data = @intFromFloat(@round(value * 256.0)) },
        else => @compileError("Unsupported type."),
    };
}

/// Get a `T` from `self` where `T` is either a float or int
pub fn to(self: Fixed, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => @as(T, @intCast(@divTrunc(self.data, 256))),
        .float => @as(T, @floatFromInt(self.data)) / 256.0,
        else => @compileError("Unsupported type."),
    };
}

/// Allow for printing of a `Fixed` using the format string `"{d}"`.
/// It will be printed as an `f64`.
pub fn formatNumber(self: Fixed, writer: *std.io.Writer, number: std.fmt.Number) !void {
    try writer.printFloat(self.to(f64), number);
}

test "to/from int" {
    try std.testing.expectEqual(0, Fixed.from(0).to(i32));
    try std.testing.expectEqual(-1, Fixed.from(-1).to(i16));
    try std.testing.expectEqual(1024, Fixed.from(1024).to(usize));

    try std.testing.expectEqual(4321, Fixed.from(@as(u64, 4321)).to(isize));
}

test "to/from float" {
    try std.testing.expectApproxEqAbs(0.0, Fixed.from(0.0).to(f32), 0.001);
    try std.testing.expectApproxEqAbs(1.2, Fixed.from(1.2).to(f32), 0.001);

    try std.testing.expectApproxEqAbs(3.456, Fixed.from(@as(f64, 3.456)).to(f64), 0.0011);
}

test "float/int" {
    try std.testing.expectEqual(3, Fixed.from(3.201).to(u16));
    try std.testing.expectEqual(15.0, Fixed.from(15).to(f64));
}
