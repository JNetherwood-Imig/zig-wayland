const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.server);

const Request = wayland.MessageUnion(.{wl});
const RequestHandler = wayland.MessageHandler(Request);

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var sock_info: wayland.SocketInfo = .auto;
    var server = sock_info.listen(init, io) catch |err| {
        log.err("Failed to create {f}.", .{sock_info});
        return err;
    };
    defer server.deinit(io);

    log.info("Server running on {f}.", .{sock_info});

    var conn = try server.accept(io);
    defer conn.deinit(io);
    log.info("Got connection!", .{});

    var client_interface_buf: [32]?[:0]const u8 = @splat(null);
    var handler = RequestHandler.initBuffered(&client_interface_buf, &.{});

    const disp: wl.Display = .display;
    try handler.addObjectBounded(disp);

    while (handler.waitNextMessage(io, &conn, .none)) |req| switch (req) {
        .wl_display => |disp_req| switch (disp_req) {
            .get_registry => |get_reg| {
                log.debug("Received get registry (id = {d}).", .{get_reg.registry});
                log.warn("Registry is not implemented.", .{});
            },
            .sync => |sync| {
                const cb = sync.callback;
                try cb.done(io, &conn, 0);
            },
        },
        else => |r| log.debug("Received {any}.", .{r}),
    } else |err| switch (err) {
        error.ConnectionClosed => log.info("Client closed its connection.", .{}),
        else => |e| return e,
    }
}
