const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const hyprland = @import("hyprland_surface");
const Event = wayland.Message(.{ wl, hyprland });

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Connecto to server
    const addr = try wayland.Address.default(init);
    var conn = try wayland.Connection.init(io, gpa, addr);
    defer conn.deinit();

    const disp: wl.Display = .display;
    const reg = try disp.getRegistry(&conn);

    _ = try disp.sync(&conn);

    var comp: wl.Compositor = .invalid;
    var surface_mgr: hyprland.SurfaceManager = .invalid;

    while (conn.nextMessage(Event, .none)) |event| switch (event) {
        .wl_registry => |ev| switch (ev) {
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

    std.debug.assert(comp != .invalid);

    if (surface_mgr == .invalid) {
        std.log.err("Could not find {s} global. Are you running Hyprland?", .{
            hyprland.SurfaceManager.interface,
        });
        return error.SurfaceManagerNotFound;
    }

    const surface = try comp.createSurface(&conn);
    const hyprland_surf = try surface_mgr.getHyprlandSurface(&conn, surface);

    // We won't actually do anything now since this is just a brief demo for building
    // and using custom protocols.
    std.log.info("Created hyprland surface, exiting...", .{});

    try hyprland_surf.destroy(&conn);
    try surface.destroy(&conn);
    try surface_mgr.destroy(&conn);
}
