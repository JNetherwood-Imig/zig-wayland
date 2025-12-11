const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.client_protocol.wayland;

pub fn main() !void {
    const conn_info = zwl.getConnectInfo();
    const conn = try conn_info.connect();
    defer conn.close();

    var id_buf: [16]u32 = undefined;
    var client_alloc = zwl.FixedBufferClientIdAllocator.init(&id_buf);
    const ida = client_alloc.allocator();

    const disp = try ida.create(wl.Display);
    _ = disp;
}
