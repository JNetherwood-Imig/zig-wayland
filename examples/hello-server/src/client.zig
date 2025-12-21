const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const Event = wayland.MessageUnion(.{wl});
const EventHandler = wayland.MessageHandler(Event);
const log = std.log.scoped(.client);

pub fn main() !void {
    var id_buf: [64]u32 = undefined;
    var ida_state: wayland.IdAllocator.Bounded = .init(&id_buf, .client);
    const ida = ida_state.id_allocator();

    var buffers: wayland.Connection.Buffers = .{};
    var sock_info: wayland.SocketInfo = .auto;
    var conn = try sock_info.connect(ida, &buffers);
    defer conn.deinit();

    var proxy_buf: [64]EventHandler.Proxy = undefined;
    var handler = EventHandler.initBuffered(&proxy_buf);

    const disp = try ida.createObject(wl.Display);
    try handler.addObjectBounded(disp);

    const reg = try disp.getRegistry(&conn);
    try handler.addObjectBounded(reg);

    const sync = try disp.sync(&conn);
    try handler.addObjectBounded(sync);

    while (handler.waitNextMessage(&conn)) |msg| switch (msg) {
        .wl_registry => |ev| try handleRegistryEvent(ev),
        .wl_callback => |ev| {
            log.info("Got callback done with data {d}.", .{ev.done.callback_data});
            break;
        },
        .wl_display => |ev| switch (ev) {
            .delete_id => |id| {
                try ida.free(id.id);
                handler.delObject(id.id);
            },
            .@"error" => return error.ProtocolError,
        },
        else => unreachable,
    } else |err| return err;
}

fn handleRegistryEvent(ev: std.meta.fieldInfo(Event, .wl_registry).type) !void {
    switch (ev) {
        .global => |glob| {
            // FIXME?: Formatted messages over 64 characters are fucked,
            // I don't think that's my problem.
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
