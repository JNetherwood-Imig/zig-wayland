const std = @import("std");
const posix = std.posix;
const core = @import("core");
const protocol = @import("protocol.zig");
const WlDisplay = protocol.wayland.WlDisplay;
const Connection = core.Connection;

const DisplayConnection = @This();

display: WlDisplay,
connection: Connection,

pub fn init() !DisplayConnection {
    return .{
        .display = .{},
        .connection = initWaylandSocket() orelse try initWaylandDisplay(),
    };
}

pub fn deinit(self: *const DisplayConnection) void {
    self.connection.deinit();
}

fn initWaylandSocket() ?Connection {
    const wayland_socket = posix.getenv("WAYLAND_SOCKET") orelse return null;
    const fd = std.fmt.parseInt(posix.fd_t, wayland_socket, 10) catch return null;
    return .initFd(fd) catch null;
}

fn initWaylandDisplay() !Connection {
    const wayland_display = disp: {
        const wayland_display = posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        break :disp if (std.mem.eql(u8, wayland_display, "")) "wayland-0" else wayland_display;
    };
    return .initPath(wayland_display);
}
