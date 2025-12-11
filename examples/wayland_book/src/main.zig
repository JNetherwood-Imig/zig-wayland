const std = @import("std");
const zwl = @import("zwl");
const wl = @import("wayland");
const xdg_shell = @import("xdg_shell");
const session_management = @import("session_management");
const Allocator = std.mem.Allocator;

pub const State = struct {
    conn: zwl.Connection,
    id_alloc: zwl.ClientIdAllocator,

    display: wl.Display,
    registry: wl.Registry,

    compositor: wl.Compositor,
    seat: wl.Seat,
    keyboard: wl.Keyboard,
    pointer: wl.Pointer,
    shm: wl.Shm,
    wm_base: xdg_shell.WmBase,

    surface: wl.Surface,
    xdg_surface: xdg_shell.Surface,
    toplevel: xdg_shell.Toplevel,

    pub fn init(gpa: Allocator) !State {
        const info = zwl.getConnectInfo();
        const conn = info.connect() catch |err| {
            std.log.err(
                "Failed to connect to wayland server: {s}",
                .{@errorName(err)},
            );
            return error.ConnectionFailed;
        };
        const id_alloc = try zwl.IdAllocator.init(gpa);

        return std.mem.zeroInit(State, .{ .conn = conn, .id_alloc = id_alloc });
    }

    pub fn deinit(self: *State, gpa: Allocator) void {
        self.id_alloc.deinit(gpa);
        self.conn.close();
    }
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();

    var state = try State.init(gpa);
    defer state.deinit(gpa);
}
