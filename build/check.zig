const std = @import("std");
const wayland = @import("wayland");

pub fn main() !void {
    std.testing.refAllDecls(wayland);
}
