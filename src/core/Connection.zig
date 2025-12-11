const std = @import("std");
const IdAllocator = @import("IdAllocator.zig");
const Reader = @import("Connection/Reader.zig");
const Writer = @import("Connection/Writer.zig");
const posix = std.posix;

const Connection = @This();

handle: posix.fd_t,
ida: IdAllocator,
writer: Writer,
reader: Reader,

pub fn connect(
    info: ConnectInfo,
    ida: IdAllocator,
    buffers: *Buffers,
) ConnectError!Connection {
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
        .reader = .init(handle, &buffers.data_in, &buffers.fds_in),
        .writer = .init(handle, &buffers.data_out, &buffers.fds_out),
    };
}

pub const ConnectError = error{
    InvalidWaylandSocket,
    NoXdgRuntimeDir,
    NameTooLong,
} || posix.ConnectError || posix.SocketError;

pub fn close(self: *Connection) void {
    posix.close(self.handle);
}

pub const FlushError = Writer.FlushError;

pub fn flush(self: *Connection) FlushError!void {
    return self.writer.flush();
}

pub fn sendMessage(self: *Connection, buffer: []const u8) FlushError!void {
    try self.writer.writeData(buffer);
}

pub fn sendMessageWithFds(
    self: *Connection,
    buffer: []const u8,
    fds: []const posix.fd_t,
) Writer.FlushError!void {
    try self.writer.writeFds(fds);
    try self.writer.writeData(buffer);
}

pub const PollEventsError = posix.PollError || Reader.ReadIncomingError;

pub fn pollEvents(self: *Connection, wait: bool) PollEventsError!bool {
    var pfd = posix.pollfd{
        .fd = self.handle,
        .events = posix.POLL.IN,
        .revents = 0,
    };
    if (try posix.poll((&pfd)[0..1], if (wait) -1 else 0) == 0) return false;
    try self.reader.readIncoming();
    return true;
}

pub const ConnectInfo = union(enum) {
    socket: i32,
    name: []const u8,
    path: []const u8,
    fallback: void,

    pub fn default() ConnectInfo {
        if (posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            if (std.fmt.parseInt(i32, wayland_socket, 10)) |raw_fd| {
                return .{ .socket = raw_fd }; // TODO validate fd
            } else |_| {}
        }
        if (posix.getenv("WAYLAND_DISPLAY")) |wayland_display| {
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

    pub fn format(self: ConnectInfo, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .socket => |sock| try writer.print("socket fd '{d}'", .{sock}),
            .name => |name| try writer.print("endpoint name '{s}'", .{name}),
            .path => |path| try writer.print("path '{s}'", .{path}),
            .fallback => try writer.writeAll("fallback 'wayland-0'"),
        }
    }

    pub fn connect(
        self: ConnectInfo,
        ida: IdAllocator,
        buffers: *Buffers,
    ) ConnectError!Connection {
        return .connect(self, ida, buffers);
    }
};

pub const Buffers = struct {
    data_in: [4096]u8 = @splat(0),
    data_out: [4096]u8 = @splat(0),
    fds_in: [20]posix.fd_t = @splat(-1),
    fds_out: [20]posix.fd_t = @splat(-1),
};
