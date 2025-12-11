const std = @import("std");
const IdAllocator = @import("IdAllocator.zig");
const Writer = @import("Connection/Writer.zig");
const posix = std.posix;

const Connection = @This();

pub const ConnectInfo = @import("Connection/connect_info.zig").ConnectInfo;

handle: posix.fd_t,
ida: IdAllocator,
writer: Writer,

pub fn connect(
    info: ConnectInfo,
    ida: IdAllocator,
    read_buf: []u8,
    write_buf: []u8,
    fd_read_buf: []posix.fd_t,
    fd_write_buf: []posix.fd_t,
) ConnectError!Connection {
    _ = read_buf;
    _ = fd_read_buf;
    const handle = conn: switch (info) {
        .socket => |fd| fd: {
            switch (posix.errno(std.os.linux.fcntl(fd, std.os.linux.F.GETFD, 0))) {
                .SUCCESS => {
                    const stat = try posix.fstat(fd);
                    if (!posix.S.ISSOCK(stat.mode)) return error.InvalidWaylandSocket;
                },
                .BADF => return error.InvalidWaylandSocket,
                else => |e| return posix.unexpectedErrno(e),
            }
            break :fd fd;
        },
        .name => |name| handle: {
            const xdg_runtime_dir = posix.getenv("XDG_RUNTIME_DIR") orelse
                return error.NoXdgRuntimeDir;
            var path_buf: [108]u8 = @splat(0);
            const path = std.fmt.bufPrint(
                &path_buf,
                "{s}/{s}",
                .{ xdg_runtime_dir, name },
            ) catch return error.NameTooLong;
            const socket = try std.net.connectUnixSocket(path);
            break :handle socket.handle;
        },
        .path => |path| handle: {
            const socket = try std.net.connectUnixSocket(path);
            break :handle socket.handle;
        },
        .fallback => continue :conn .{ .name = "wayland-0" },
    };

    return Connection{
        .handle = handle,
        .ida = ida,
        .writer = .init(handle, write_buf, fd_write_buf),
    };
}

pub fn close(self: *Connection) void {
    posix.close(self.handle);
}

pub fn sendMessage(self: *Connection, buffer: []const u8) !void {
    try self.writer.writeData(buffer);
}

pub fn sendMessageWithFds(
    self: *Connection,
    buffer: []const u8,
    fds: []const posix.fd_t,
) !void {
    try self.writer.writeFds(fds);
    try self.writer.writeData(buffer);
}

pub const ConnectError = error{
    InvalidWaylandSocket,
    NoXdgRuntimeDir,
    NameTooLong,
} || posix.ConnectError || posix.SocketError;
