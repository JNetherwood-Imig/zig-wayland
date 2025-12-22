const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_protocol");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.server);

const Request = wayland.MessageUnion(.{wl});
const RequestHandler = wayland.MessageHandler(Request);

pub fn main() !void {
    var sock_info: wayland.SocketInfo = .auto;
    const server = sock_info.listen() catch |err| {
        log.err("Failed to create {f}.", .{sock_info});
        return err;
    };
    defer server.close();

    log.info("Server running on {f}.", .{sock_info});

    if (server.waitForConnection(10 * std.time.ms_per_s)) {
        log.info("Got connection!", .{});

        var ida_buf: [32]u32 = undefined;
        var ida_state = wayland.IdAllocator.Bounded.init(&ida_buf, .client);
        const ida = ida_state.id_allocator();

        var conn = try server.accept(ida);
        defer conn.deinit();

        var proxy_buf: [32]RequestHandler.Proxy = undefined;
        var handler = RequestHandler.initBuffered(&proxy_buf);

        const disp = try ida.createObject(wl.Display);
        try handler.addObjectBounded(disp);

        while (handler.waitNextMessage(&conn)) |req| switch (req) {
            .wl_display => |disp_req| switch (disp_req) {
                .get_registry => |get_reg| {
                    log.debug("Received get registry (id = {d}).", .{get_reg.registry});
                    log.warn("Registry is not implemented.", .{});
                },
                .sync => |sync| {
                    const cb = sync.callback;
                    try cb.done(&conn, 0);
                },
            },
            else => |r| log.debug("Received {any}.", .{r}),
        } else |err| switch (err) {
            error.ConnectionClosed => log.info("Client closed its connection.", .{}),
            else => |e| return e,
        }
    } else |_| log.info("Timed out, exiting...", .{});
}
