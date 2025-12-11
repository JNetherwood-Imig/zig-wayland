const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;
const xdg = zwl.protocol.xdg_shell;
const shm_util = @import("shm.zig");

const width = 128;
const height = 128;

var conn: zwl.Connection = undefined;

var disp = wl.Display.null_handle;
var reg = wl.Registry.null_handle;

var comp = wl.Compositor.null_handle;
var shm = wl.Shm.null_handle;
var wm_base = xdg.WmBase.null_handle;

var shm_data: []align(4096) u8 = &.{};
var surf = wl.Surface.null_handle;
var toplevel = xdg.Toplevel.null_handle;

var configured: bool = false;

pub fn main() !void {
    var id_buf: [16]u32 = undefined;
    var ida_state = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.allocator();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var fd_read_buf: [20]i32 = undefined;
    var fd_write_buf: [20]i32 = undefined;

    conn = try zwl.getConnectInfo().connect(ida, &read_buf, &write_buf, &fd_read_buf, &fd_write_buf);
    var proxy_buf: [16]zwl.EventHandler.Proxy = undefined;
    var handler = zwl.EventHandler.initBuffered(&proxy_buf);

    disp = try ida.createObject(wl.Display);
    try handler.addObjectBounded(disp);
    reg = try disp.getRegistry(&conn);
    try handler.addObjectBounded(reg);

    const sync_cb = try disp.sync(&conn);
    try handler.addObjectBounded(sync_cb);

    var ev_buf: [4096]u8 = undefined;
    while (handler.waitNextEvent(&conn, &ev_buf)) |event| switch (event) {
        .wl_callback => break,
        .wl_registry => |ev| switch (ev) {
            .global => |g| {
                if (std.mem.eql(u8, g.interface, wl.Compositor.interface)) {
                    comp = try reg.bind(&conn, wl.Compositor, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, wl.Shm.interface)) {
                    shm = try reg.bind(&conn, wl.Shm, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, xdg.WmBase.interface)) {
                    wm_base = try reg.bind(&conn, xdg.WmBase, .v1, g.name);
                    try handler.addObjectBounded(wm_base);
                }
            },
            else => {},
        },
        else => std.log.err("Unexpected event: {any}.", .{event}),
    } else |e| return e;
    std.debug.assert(comp != .null_handle and shm != .null_handle and wm_base != .null_handle);

    surf = try comp.createSurface(&conn);
    try handler.addObjectBounded(surf);
    const xdg_surf = try wm_base.getXdgSurface(&conn, surf);
    try handler.addObjectBounded(xdg_surf);
    toplevel = try xdg_surf.getToplevel(&conn);
    try handler.addObjectBounded(toplevel);

    try surf.commit(&conn);

    while (handler.waitNextEvent(&conn, &ev_buf)) |event| switch (event) {
        .xdg_wm_base => |ev| try wm_base.pong(&conn, ev.ping.serial),
        .xdg_surface => |ev| {
            try ev.configure.xdg_surface.ackConfigure(&conn, ev.configure.serial);
            if (!configured) {
                const buffer = try createBuffer();
                try surf.attach(&conn, buffer, 0, 0);
            }
            try surf.commit(&conn);
        },
        .xdg_toplevel => |ev| switch (ev) {
            .close => break,
            else => {},
        },
        .wl_display => |ev| switch (ev) {
            .@"error" => return error.ProtocolError,
            .delete_id => |id| {
                handler.delObject(id.id);
                try ida.free(id.id);
            },
        },
        else => {},
    } else |e| return e;

    if (shm_data.len > 0) std.posix.munmap(shm_data);
}

fn createBuffer() !wl.Buffer {
    const stride = width * 4;
    const size = stride * height;

    const fd = try shm_util.allocateShmFile(size);
    defer std.posix.close(fd);

    shm_data = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    const pool = try shm.createPool(&conn, fd, size);
    defer pool.destroy(&conn) catch {};
    const buffer = try pool.createBuffer(&conn, 0, width, height, stride, .argb8888);
    @memset(shm_data, 255);
    try conn.writer.flush();
    return buffer;
}
