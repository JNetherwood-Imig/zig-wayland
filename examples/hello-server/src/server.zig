const std = @import("std");

const wayland = @import("wayland");
const wl = @import("wayland_protocol");

const log = std.log.scoped(.server);

const Request = wayland.Message(.{wl});

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var server = try wayland.Server.init(init, io);
    defer server.deinit(io);

    log.info("Server running on {s}.", .{server.socketPath()});

    var conn = try server.accept(io, gpa);
    defer conn.deinit();
    log.info("Got connection!", .{});

    while (conn.nextMessage(Request, .none)) |request| switch (request) {
        .wl_display => |req| switch (req) {
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
}
