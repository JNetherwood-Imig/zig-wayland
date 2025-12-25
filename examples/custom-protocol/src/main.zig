const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const hyprland = @import("hyprland_surface");
const Event = wayland.MessageUnion(.{ wl, hyprland });
const EventHandler = wayland.MessageHandler(Event);

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // Setup ID allocator
    var ida_state = try wayland.IdAllocator.Unbounded.init(gpa, .client, 8);
    defer ida_state.deinit();
    const ida = ida_state.id_allocator();

    // Connecto to server
    var sock_info: wayland.SocketInfo = .auto;
    var conn = try sock_info.connect(ida);
    defer conn.deinit();

    // Initialize event handler
    var handler = try EventHandler.initCapacity(gpa, 8);
    defer handler.deinit(gpa);

    const disp: wl.Display = .display;
    try handler.addObject(gpa, disp);

    const reg = try disp.getRegistry(&conn);
    try handler.addObject(gpa, reg);

    const sync_cb = try disp.sync(&conn);
    try handler.addObject(gpa, sync_cb);

    var comp: wl.Compositor = .invalid;
    var surface_mgr: hyprland.SurfaceManager = .invalid;

    while (handler.waitNextMessage(&conn)) |ev| switch (ev) {
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
