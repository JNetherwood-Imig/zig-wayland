const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const Event = wayland.MessageUnion(.{wl});
const EventHandler = wayland.MessageHandler(Event);
const log = std.log.scoped(.client);

pub fn main() !void {
    var id_buf: [8]u32 = undefined;
    var ida = wayland.IdAllocator.initBounded(.client, &id_buf);

    var sock_info: wayland.SocketInfo = .auto;
    var conn = try sock_info.connect();
    defer conn.deinit();

    var client_interface_buf: [64]?[:0]const u8 = @splat(null);
    var handler = EventHandler.initBuffered(&client_interface_buf, &.{});

    const disp: wl.Display = .display;
    try handler.addObjectBounded(disp);

    const reg = try disp.getRegistry(&conn, &ida);
    try handler.addObjectBounded(reg);

    const sync = try disp.sync(&conn, &ida);
    try handler.addObjectBounded(sync);

    while (handler.waitNextMessage(&conn)) |msg| switch (msg) {
        .wl_registry => |ev| try handleRegistryEvent(ev),
        .wl_callback => |ev| {
            log.info("Got callback done with data {d}.", .{ev.done.callback_data});
            break;
        },
        .wl_display => |ev| switch (ev) {
            .delete_id => |id| {
                try ida.freeBounded(id.id);
                try handler.delObject(id.id);
            },
            .@"error" => return error.ProtocolError,
        },
        else => unreachable,
    } else |err| return err;
}

fn handleRegistryEvent(ev: std.meta.fieldInfo(Event, .wl_registry).type) !void {
    switch (ev) {
        .global => |glob| {
            log.info("Global: {d}: {s} (version {d}).", .{
                glob.name,
                glob.interface,
                glob.version,
            });
        },
        .global_remove => |glob| {
            log.info("Removed global: {d}.", .{glob.name});
        },
    }
}
