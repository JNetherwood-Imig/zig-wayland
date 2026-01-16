const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const hyprland = @import("hyprland_surface");
const Event = wayland.MessageUnion(.{ wl, hyprland });
const EventHandler = wayland.MessageHandler(Event);

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Setup ID allocator
    var ida: wayland.IdAllocator = .empty_client;

    // Connecto to server
    var sock_info: wayland.SocketInfo = .auto;
    var conn = try sock_info.connect(init, io);
    defer conn.deinit(io);

    // Initialize event handler
    var handler = try EventHandler.initCapacity(gpa, 8);
    defer handler.deinit(gpa);

    const disp: wl.Display = .display;
    try handler.addObject(gpa, disp);

    const reg = try disp.getRegistry(io, &conn, &ida);
    try handler.addObject(gpa, reg);

    const sync_cb = try disp.sync(io, &conn, &ida);
    try handler.addObject(gpa, sync_cb);

    var comp: wl.Compositor = .invalid;
    var surface_mgr: hyprland.SurfaceManager = .invalid;

    while (handler.waitNextMessage(io, &conn, .none)) |ev| switch (ev) {
        .wl_registry => |reg_ev| switch (reg_ev) {
            .global => |glob| {
                if (std.mem.eql(u8, glob.interface, wl.Compositor.interface)) {
                    comp = try reg.bind(io, &conn, &ida, wl.Compositor, .v6, glob.name);
                    continue;
                }
                if (std.mem.eql(u8, glob.interface, hyprland.SurfaceManager.interface)) {
                    std.log.info("Found hyprland surface manager.", .{});
                    surface_mgr = try reg.bind(io, &conn, &ida, hyprland.SurfaceManager, .v2, glob.name);
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

    const surface = try comp.createSurface(io, &conn, &ida);
    const hyprland_surf = try surface_mgr.getHyprlandSurface(io, &conn, &ida, surface);

    // We won't actually do anything now since this is just a brief demo for building
    // and using custom protocols.
    std.log.info("Created hyprland surface, exiting...", .{});

    try hyprland_surf.destroy(io, &conn);
    try surface.destroy(io, &conn);

    try surface_mgr.destroy(io, &conn);
}
