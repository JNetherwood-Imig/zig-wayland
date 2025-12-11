const Connection = @This();

handle: std.posix.fd_t,
ida: IdAllocator,

pub fn connect(info: ConnectInfo, ida: IdAllocator) ConnectError!Connection {
    const handle = conn: switch (info) {
        .socket => |fd| fd: {
            switch (posix.errno(std.os.linux.fcntl(fd, std.os.linux.F.GETFD, 0))) {
                .SUCCESS => {
                    const stat = try posix.fstat(fd);
                    if (!posix.S.ISSOCK(stat.mode)) return error.InvalidWaylandSocket;
                },
                .BADF => return error.InvalidWaylandSocket,
                else => |e| return std.posix.unexpectedErrno(e),
            }
            break :fd fd;
        },
        .name => |name| handle: {
            const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse
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

    return Connection{ .handle = handle, .ida = ida };
}

pub fn close(self: *Connection) void {
    std.posix.close(self.handle);
}

pub fn sendMessage(self: *Connection, buffer: []const u8) !void {
    const header = std.mem.bytesAsValue(wire.Header, buffer[0..8]);
    _ = try posix.send(self.handle, buffer[0..header.length], 0);
}

pub fn sendMessageWithFds(
    self: *Connection,
    buffer: []const u8,
    comptime fd_count: usize,
    fds: []const i32,
) !void {
    const header = std.mem.bytesAsValue(wire.Header, buffer[0..8]);
    var control = cmsg.MsgUnion(fd_count).init();
    @memcpy(
        cmsg.data(&control.header)[0 .. fd_count * @sizeOf(i32)],
        std.mem.sliceAsBytes(fds),
    );
    const msg = posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &.{.{ .base = buffer.ptr, .len = header.length }},
        .iovlen = 1,
        .control = &control.buffer,
        .controllen = control.header.cmsg_len,
        .flags = 0,
    };
    _ = try posix.sendmsg(self.handle, &msg, 0);
}

pub const ConnectError = error{
    InvalidWaylandSocket,
    NoXdgRuntimeDir,
    NameTooLong,
} || std.posix.ConnectError || std.posix.SocketError;

pub const ConnectInfo = union(enum) {
    socket: i32,
    name: []const u8,
    path: []const u8,
    fallback: void,

    pub fn default() ConnectInfo {
        if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            if (std.fmt.parseInt(i32, wayland_socket, 10)) |raw_fd| {
                return .{ .socket = raw_fd }; // TODO validate fd
            } else |_| {}
        }
        if (std.posix.getenv("WAYLAND_DISPLAY")) |wayland_display| {
            if (std.fs.path.isAbsolute(wayland_display))
                return .{ .path = wayland_display }
            else
                return .{ .name = wayland_display };
        }
        return .fallback;
    }

    pub fn initSocket(socket: posix.fd_t) ConnectInfo {
        return .{ .socket = socket };
    }

    pub fn initName(name: []const u8) ConnectInfo {
        return .{ .name = name };
    }

    pub fn initPath(path: []const u8) ConnectInfo {
        return .{ .path = path };
    }

    pub fn format(self: ConnectInfo, writer: *Writer) Writer.Error!void {
        switch (self) {
            .socket => |sock| try writer.print("socket fd '{d}'", .{sock}),
            .name => |name| try writer.print("endpoint name '{s}'", .{name}),
            .path => |path| try writer.print("path '{s}'", .{path}),
            .fallback => try writer.writeAll("fallback 'wayland-0'"),
        }
    }

    pub fn connect(self: ConnectInfo, ida: IdAllocator) ConnectError!Connection {
        return Connection.connect(self, ida);
    }
};

const std = @import("std");
const util = @import("util");
const wire = @import("wire.zig");
const IdAllocator = @import("IdAllocator.zig");

const posix = std.posix;
const cmsg = util.cmsg;
const Writer = std.Io.Writer;
