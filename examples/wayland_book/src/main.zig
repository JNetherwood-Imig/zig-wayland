const std = @import("std");
const zwl = @import("zwl");
const protocol = @import("protocol");
const wl = protocol.wayland;
const xdg = protocol.xdg_shell;

pub fn main() !void {
    const conn_info = zwl.getConnectInfo();
    const conn = try conn_info.connect();
    defer conn.close();

    var id_buf: [16]u32 = undefined;
    var client_alloc = zwl.FixedBufferClientIdAllocator.init(&id_buf);
    const ida = client_alloc.allocator();
    _ = ida;
}
