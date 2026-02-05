//! Simple listener to accept Wayland client connections.

const std = @import("std");
const sys = std.posix.system;
const Address = @import("Addresss.zig");

const Connection = @import("Connection.zig");

const Server = @This();

inner: std.Io.net.Server,
/// If the server created its own socket file, then it must be removed from the filesystem at
/// shutdown by calling `unlink`, which requiers a path.
path: [std.Io.net.UnixAddress.max_len:0]u8 = @splat(0),

/// Close the socket file descriptor and remove the socket file from the filesystem unless it was
/// manually created by the user.
pub fn deinit(self: *Server, io: std.Io) void {
    const path: [:0]const u8 = std.mem.sliceTo(&self.path, 0);
    if (path.len > 0 and path.len < self.path.len)
        _ = sys.unlink(path.ptr);
    self.inner.deinit(io);
}

pub const AcceptError = std.Io.net.Server.AcceptError;

/// Accept an incoming client connection and return a `Connection` to exchange messages
/// with the new client.
pub fn accept(self: *Server, io: std.Io, gpa: std.mem.Allocator) AcceptError!Connection {
    const stream = try self.inner.accept(io);
    return Connection.fromStreamUnbounded(io, gpa, stream, .server);
}
