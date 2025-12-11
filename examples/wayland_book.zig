const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;

pub fn main() !void {
    const conn_info = zwl.getConnectInfo();
    var conn = try conn_info.connect();
    defer conn.close();

    var id_buf: [16]u32 = undefined;
    var client_alloc = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = client_alloc.allocator();

    const disp = try ida.create(wl.Display);
    const reg = try disp.getRegistry(&conn, ida);
    const compositor = try reg.bind(wl.Compositor, .v6, &conn, ida);
    const surface = try compositor.createSurface(&conn, ida);
    try surface.damage(&conn, 0, 0, 100, 100);
    try surface.commit(&conn);
}
