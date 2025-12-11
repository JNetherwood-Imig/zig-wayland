const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const conn_info = zwl.getConnectInfo();
    var conn = try conn_info.connect();
    defer conn.close();

    var id_buf: [16]u32 = undefined;
    var ida_state = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.allocator();

    var handler = try zwl.EventHandler.init(gpa);
    defer handler.deinit(gpa);

    const disp = try ida.create(wl.Display);
    try handler.addObject(gpa, disp);
    const reg = try disp.getRegistry(&conn, ida);
    try handler.addObject(gpa, reg);

    while (handler.waitNextEvent(&conn)) |ev| {
        _ = ev;
    } else |err| return err;
}
