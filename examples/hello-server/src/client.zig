const std = @import("std");

const wayland = @import("wayland");
const wl = @import("wayland_protocol");

const Event = wayland.Message(.{wl});
const log = std.log.scoped(.client);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const addr = try wayland.Address.default(init);
    var conn = try wayland.Connection.init(io, gpa, addr);
    defer conn.deinit(gpa);

    const disp: wl.Display = .display;
    _ = try disp.getRegistry(&conn, gpa);
    _ = try disp.sync(&conn, gpa);

    while (conn.nextMessage(Event, .none)) |msg| switch (msg) {
        .wl_registry => |ev| try handleRegistryEvent(ev),
        .wl_callback => |ev| {
            log.info("Got callback done with data {d}.", .{ev.done.callback_data});
            break;
        },
        .wl_display => |ev| switch (ev) {
            .delete_id => |id| try conn.releaseObject(gpa, id.id),
            .@"error" => return error.ProtocolError,
        },
        else => unreachable,
    } else |err| return err;
}

fn handleRegistryEvent(ev: @FieldType(Event, "wl_registry")) !void {
    switch (ev) {
        .global => |glob| log.info("Global: {d}: {s} (version {d}).", .{
            glob.name,
            glob.interface,
            glob.version,
        }),
        .global_remove => |glob| log.info("Removed global: {d}.", .{glob.name}),
    }
}
