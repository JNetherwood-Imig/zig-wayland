const std = @import("std");
const wayland = @import("wayland");
// const wl = @import("wayland_protocol");
const Allocator = std.mem.Allocator;

const Client = struct {
    connection: wayland.Connection,
    buffers: wayland.Connection.Buffers,
    ida_state: wayland.IdAllocator.Unbounded,
    ida: wayland.IdAllocator,

    pub fn create(gpa: Allocator) !*Client {
        const self = try gpa.create(Client);
        self.* = Client{
            .connection = undefined,
            .buffers = .{},
            .ida_state = try .init(gpa, .server, .{}),
            .ida = undefined,
        };
        self.ida = self.ida_state.id_allocator();
        return self;
    }

    pub fn destroy(self: *Client, gpa: Allocator) void {
        self.connection.deinit();
        self.ida_state.deinit();
        gpa.destroy(self);
    }
};

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var sock_info: wayland.SocketInfo = .auto;
    const server = sock_info.listen() catch |err| {
        std.log.err("Failed to create {f}.", .{sock_info});
        return err;
    };
    defer server.close();

    std.log.info("Server running on {f}.", .{sock_info});

    while (server.waitForConnection(10 * std.time.ms_per_s)) {
        std.log.info("Got connection!", .{});

        const client = try Client.create(gpa);
        defer client.destroy(gpa);

        const conn = try server.accept(client.ida, &client.buffers);
        client.connection = conn;
    } else |_| std.log.info("Timed out, exiting...", .{});
}
