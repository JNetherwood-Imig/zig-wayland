//! Simple listener to accept Wayland client connections.

const std = @import("std");
const Connection = @import("Connection.zig");
const posix = std.posix;

const Server = @This();

handle: std.posix.fd_t,
/// If the server created its own socket file, then it must be removed from the filesystem at
/// shutdown by calling `unlink`, which requiers a path.
addr: ?std.net.Address,

/// Close the socket file descriptor and remove the socket file from the filesystem unless it was
/// manually created by the user.
pub fn close(self: Server) void {
    if (self.addr) |addr|
        posix.unlink(std.mem.sliceTo(&addr.un.path, 0)) catch {};
    posix.close(self.handle);
}

/// Wait for an incoming connection attempt.
/// `timeout` is in milliseconds and timeout of -1 will wait indefinately.
pub fn waitForConnection(self: Server, timeout: i32) !void {
    var pfd = [1]posix.pollfd{.{
        .events = posix.POLL.IN,
        .fd = self.handle,
        .revents = 0,
    }};
    if (try posix.poll(&pfd, timeout) == 0)
        return error.Timeout;
}

pub const AcceptError = posix.AcceptError;

/// Accept an incoming client connection and return a `Connection` to exchange messages
/// with the new client.
pub fn accept(self: Server) AcceptError!Connection {
    return Connection{ .handle = try posix.accept(self.handle, null, null, 0) };
}
