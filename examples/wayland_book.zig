const std = @import("std");
const denali = @import("denali");

pub fn main() !void {
    const conn = try denali.DisplayConnection.init();
    defer conn.deinit();
}
