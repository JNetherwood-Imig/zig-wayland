const std = @import("std");
const Connection = @import("Connection.zig");
const IdAllocator = @import("IdAllocator.zig");
const posix = std.posix;

const Server = @This();

addr: ?std.net.Address,
handle: std.posix.fd_t,

/// Close the backing file descriptor.
pub fn close(self: Server) void {
    if (self.addr) |addr| {
        posix.unlink(std.mem.sliceTo(&addr.un.path, 0)) catch {};
    }
    posix.close(self.handle);
}

/// Wait for an incoming connection attempt.
/// `timeout` is in milliseconds and passing -1 will wait indefinately.
pub fn waitForConnection(self: Server, timeout: i32) !void {
    while (true) {
        var pfd = [1]posix.pollfd{.{
            .events = posix.POLL.IN,
            .fd = self.handle,
            .revents = 0,
        }};
        if (try posix.poll(&pfd, timeout) > 0) break;
    }
}

pub const AcceptError = posix.AcceptError;

/// Accept an incoming client connection and return a `Connection` to handle messages.
pub fn accept(self: Server, ida: IdAllocator, buffers: *Connection.Buffers) AcceptError!Connection {
    const conn_fd = try posix.accept(self.handle, null, null, 0);
    return .init(conn_fd, ida, buffers);
}
