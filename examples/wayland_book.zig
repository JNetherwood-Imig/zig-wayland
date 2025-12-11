const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;
const xdg = zwl.protocol.xdg_shell;
const Allocator = std.mem.Allocator;

const State = struct {
    conn: zwl.Connection,
    ida: zwl.IdAllocator,
    handler: zwl.EventHandler,

    display: wl.Display,
    registry: wl.Registry,
    compositor: wl.Compositor,
    shm: wl.Shm,
    seat: wl.Seat,
    shell: xdg.WmBase,

    surface: wl.Surface,
    xdg_surface: xdg.Surface,
    toplevel: xdg.Toplevel,

    pub fn init(gpa: Allocator, ida: zwl.IdAllocator) !State {
        const conn_info = zwl.getConnectInfo();
        var conn = conn_info.connect() catch |err| {
            std.log.err("Failed to connect to wayland server: {t} ({f}).", .{ err, conn_info });
            return err;
        };
        errdefer conn.close();

        var handler = try zwl.EventHandler.init(gpa);
        errdefer handler.deinit(gpa);

        const display = try ida.create(wl.Display);
        try handler.addObject(gpa, display);
        const registry = try display.getRegistry(&conn, ida);
        try handler.addObject(gpa, registry);

        const compositor, const shm, const seat, const shell = blk: {
            var buf: [4096]u8 = undefined;
            const sync_callback = try display.sync(&conn, ida);
            try handler.addObject(gpa, sync_callback);
            var compositor: ?wl.Compositor = null;
            var shm: ?wl.Shm = null;
            var seat: ?wl.Seat = null;
            var shell: ?xdg.WmBase = null;
            while (handler.waitNextEvent(&conn, &buf)) |ev| switch (ev) {
                .wl_display => |disp| switch (disp) {
                    .@"error" => return error.ProtocolError,
                    .delete_id => |id| {
                        try handler.delObject(id.id);
                        try ida.free(id.id);
                        if (id.id == sync_callback.getId()) break;
                    },
                },
                .wl_callback => |cb| std.debug.assert(cb.done.wl_callback == sync_callback),
                .wl_registry => |reg_ev| switch (reg_ev) {
                    .global => |glob| {
                        if (std.mem.eql(u8, glob.interface, wl.Compositor.interface)) {
                            compositor = try registry.bind(&conn, ida, wl.Compositor, .v6, glob.name);
                        } else if (std.mem.eql(u8, glob.interface, wl.Shm.interface)) {
                            shm = try registry.bind(&conn, ida, wl.Shm, .v2, glob.name);
                        } else if (std.mem.eql(u8, glob.interface, wl.Seat.interface)) {
                            seat = try registry.bind(&conn, ida, wl.Seat, .v9, glob.name);
                        } else if (std.mem.eql(u8, glob.interface, xdg.WmBase.interface)) {
                            shell = try registry.bind(&conn, ida, xdg.WmBase, .v6, glob.name);
                        }
                    },
                    .global_remove => continue,
                },
                else => std.log.warn("Unexpected event: {}.", .{ev}),
            } else |err| return err;

            break :blk .{
                compositor orelse return error.NoCompositor,
                shm orelse return error.NoShm,
                seat orelse return error.NoSeat,
                shell orelse return error.NoXdgShell,
            };
        };

        try handler.addObject(gpa, compositor);
        try handler.addObject(gpa, shm);
        try handler.addObject(gpa, seat);
        try handler.addObject(gpa, shell);

        const surface = try compositor.createSurface(&conn, ida);
        try handler.addObject(gpa, surface);
        const xdg_surface = try shell.getXdgSurface(&conn, ida, surface);
        try handler.addObject(gpa, xdg_surface);
        const toplevel = try xdg_surface.getToplevel(&conn, ida);
        try handler.addObject(gpa, toplevel);

        return State{
            .conn = conn,
            .ida = ida,
            .handler = handler,
            .display = display,
            .registry = registry,
            .compositor = compositor,
            .shm = shm,
            .seat = seat,
            .shell = shell,
            .surface = surface,
            .xdg_surface = xdg_surface,
            .toplevel = toplevel,
        };
    }

    pub fn run(self: *State, gpa: Allocator) !void {
        _ = gpa;
        var buf: [4096]u8 = undefined;
        while (self.handler.waitNextEvent(&self.conn, &buf)) |ev| switch (ev) {
            .wl_display => |disp| switch (disp) {
                .@"error" => |e| {
                    std.log.err("Protocol error: object {d}: code {d}: {s}.", .{
                        e.object_id,
                        e.code,
                        e.message,
                    });
                    return error.ProtocolError;
                },
                .delete_id => |id| {
                    try self.handler.delObject(id.id);
                    try self.ida.free(id.id);
                },
            },
            else => std.log.warn("Unhandled message: {}.", .{ev}),
        } else |err| return err;
    }

    pub fn deinit(self: *State, gpa: Allocator) void {
        self.conn.close();
        self.handler.deinit(gpa);
    }
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var id_buf: [16]u32 = undefined;
    var ida_state = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.allocator();

    var state = try State.init(gpa, ida);
    defer state.deinit(gpa);

    try state.run(gpa);
}
