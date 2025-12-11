const std = @import("std");
const testing = std.testing;
const Fixed = @This();

data: i32,

pub fn from(value: anytype) Fixed {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => Fixed{ .data = @intCast(value * 256) },
        .float, .comptime_float => Fixed{ .data = @intFromFloat(@round(value * 256.0)) },
        else => @compileError("Unsupported type."),
    };
}

pub fn to(self: Fixed, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => @as(T, @intCast(@divTrunc(self.data, 256))),
        .float => @as(T, @floatFromInt(self.data)) / 256.0,
        else => @compileError("Unsupported type."),
    };
}

pub fn formatNumber(self: Fixed, writer: *std.io.Writer, number: std.fmt.Number) !void {
    try writer.printFloat(self.to(f64), number);
}

test "to/from int" {
    try testing.expectEqual(0, Fixed.from(0).to(i32));
    try testing.expectEqual(-1, Fixed.from(-1).to(i16));
    try testing.expectEqual(1024, Fixed.from(1024).to(usize));

    try testing.expectEqual(4321, Fixed.from(@as(u64, 4321)).to(isize));
}

test "to/from float" {
    try testing.expectApproxEqAbs(0.0, Fixed.from(0.0).to(f32), 0.001);
    try testing.expectApproxEqAbs(1.2, Fixed.from(1.2).to(f32), 0.001);

    try testing.expectApproxEqAbs(3.456, Fixed.from(@as(f64, 3.456)).to(f64), 0.0011);
}

test "float/int" {
    try testing.expectEqual(3, Fixed.from(3.201).to(u16));
    try testing.expectEqual(15.0, Fixed.from(15).to(f64));
}
