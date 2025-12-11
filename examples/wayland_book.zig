const std = @import("std");
const zwl = @import("zwl");
const client_protocol = @import("client_protocol");
const wl = client_protocol.wayland;

pub fn main() !void {
    const conn_info = zwl.getConnectInfo();
    var conn = try conn_info.connect();
    defer conn.close();

    var id_buf: [16]u32 = undefined;
    var client_alloc = zwl.FixedBufferClientIdAllocator.init(&id_buf);
    const ida = client_alloc.allocator();

    const disp = try ida.create(wl.Display);
    const reg = try disp.getRegistry(&conn, ida);
    _ = reg;
}
