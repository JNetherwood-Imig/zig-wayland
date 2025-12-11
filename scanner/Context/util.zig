pub fn snakeToPascal(gpa: Allocator, snake: []const u8) ![]u8 {
    var pascal = try std.ArrayList(u8).initCapacity(gpa, snake.len);
    var it = std.mem.tokenizeScalar(u8, snake, '_');

    while (it.next()) |tok| {
        pascal.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        if (tok.len > 1) pascal.appendSliceAssumeCapacity(tok[1..]);
    }

    return try pascal.toOwnedSlice(gpa);
}

pub fn snakeToCamel(gpa: Allocator, snake: []const u8) ![]u8 {
    var camel = try snakeToPascal(gpa, snake);
    camel[0] = std.ascii.toLower(camel[0]);
    return camel;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
