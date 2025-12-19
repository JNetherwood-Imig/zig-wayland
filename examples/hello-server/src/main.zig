const std = @import("std");
const wayland = @import("wayland");
// const wl = @import("wayland_protocol");

pub fn main() !void {
    var sock_info: wayland.SocketInfo = .auto;
    const server = sock_info.listen() catch |err| {
        std.log.err("Failed to create {f}.", .{sock_info});
        return err;
    };
    defer server.close();

    std.log.info("Server running on {f}.", .{sock_info});
}
