handle: Fd,

pub fn connect(info: ConnectInfo) ConnectError!Connection {
    const handle = conn: switch (info) {
        .socket => |socket| socket,
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
            break :handle Fd.initUnchecked(socket.handle);
        },
        .path => |path| handle: {
            const socket = try std.net.connectUnixSocket(path);
            break :handle Fd.initUnchecked(socket.handle);
        },
        .fallback => continue :conn .{ .name = "wayland-0" },
    };
    return Connection{ .handle = handle };
}

pub fn close(self: Connection) void {
    self.handle.close();
}

pub const ConnectError = error{
    NoXdgRuntimeDir,
    NameTooLong,
} || std.posix.ConnectError || std.posix.SocketError;

pub const ConnectInfo = union(enum) {
    socket: Fd,
    name: []const u8,
    path: []const u8,
    fallback: void,

    pub fn default() ConnectInfo {
        if (std.posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            if (std.fmt.parseInt(i32, wayland_socket, 10)) |raw_fd| {
                if (Fd.init(raw_fd)) |fd| return .{ .socket = fd } else |_| {}
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

    pub fn connect(self: ConnectInfo) ConnectError!Connection {
        return Connection.connect(self);
    }
};

const std = @import("std");
const posix = std.posix;
const log = std.log.scoped(.wayland);
const Writer = std.Io.Writer;

const wire = @import("wire.zig");
const Fd = @import("Fd.zig");

const Connection = @This();
