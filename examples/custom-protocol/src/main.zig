const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const hyprland = @import("hyprland_surface");
const Event = wayland.EventUnion(.{ wl, hyprland });
const EventHandler = wayland.EventHandler(Event);

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // Setup ID allocator
    var ida_state = try wayland.IdAllocator.Unbounded.init(gpa, .client, .{});
    defer ida_state.deinit();
    const ida = ida_state.id_allocator();

    // Setup backing buffers for connection
    var buffers = wayland.Connection.Buffers{};

    // Connecto to server
    const conn_info = wayland.ConnectInfo.getDefault();
    var conn = try conn_info.connect(ida, &buffers);
    defer conn.close();

    // Initialize event handler with default capacity of 64 objects to be tracked
    var handler = try EventHandler.initCapacity(gpa, 64);
    defer handler.deinit(gpa);

    const disp = try ida.createObject(wl.Display);
    try handler.addObject(gpa, disp);

    const reg = try disp.getRegistry(&conn);
    try handler.addObject(gpa, reg);

    const sync_cb = try disp.sync(&conn);
    try handler.addObject(gpa, sync_cb);

    var comp: wl.Compositor = .null_handle;
    var surface_mgr: hyprland.SurfaceManager = .null_handle;

    while (handler.waitNextEvent(&conn)) |ev| switch (ev) {
        .wl_registry => |reg_ev| switch (reg_ev) {
            .global => |glob| {
                if (std.mem.eql(u8, glob.interface, wl.Compositor.interface)) {
                    comp = try reg.bind(&conn, wl.Compositor, .v6, glob.name);
                    continue;
                }
                if (std.mem.eql(u8, glob.interface, hyprland.SurfaceManager.interface)) {
                    std.log.info("Found hyprland surface manager.", .{});
                    surface_mgr = try reg.bind(&conn, hyprland.SurfaceManager, .v2, glob.name);
                    continue;
                }
            },
            .global_remove => {},
        },
        .wl_callback => break,
        else => {},
    } else |err| return err;

    std.debug.assert(comp != .null_handle and surface_mgr != .null_handle);

    const surface = try comp.createSurface(&conn);
    const hyprland_surf = try surface_mgr.getHyprlandSurface(&conn, surface);

    // We won't actually do anything now since this is just a brief demo for building
    // and using custom protocols.
    std.log.info("Created hyprland surface, exiting...", .{});

    try hyprland_surf.destroy(&conn);
    try surface.destroy(&conn);

    try surface_mgr.destroy(&conn);
}
