const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wl");
const Event = wayland.Message(.{wl});

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const addr = try wayland.Address.default(init);
    var conn = wayland.Connection.init(io, gpa, addr) catch |err| {
        std.log.err("Failed to connect to {f}: {t}.", .{ addr, err });
        return err;
    };
    defer conn.deinit(gpa);

    const display: wl.Display = .display;
    _ = try display.getRegistry(&conn, gpa);

    _ = try display.sync(&conn, gpa);
    while (conn.nextMessage(Event, .none)) |event| switch (event) {
        .wl_registry => |ev| switch (ev) {
            .global => |global| std.log.info("Received global {d}: {s} (v{d}).", .{
                global.name,
                global.interface,
                global.version,
            }),
            .global_remove => {},
        },
        .wl_callback => break,
        else => |ev| std.log.err("Unexpected event: {}.", .{ev}),
    } else |err| return err;
}
