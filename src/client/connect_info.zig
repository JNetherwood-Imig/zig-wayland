const std = @import("std");
const core = @import("core");
const posix = std.posix;
const Connection = core.Connection;
const Buffers = Connection.Buffers;
const IdAllocator = core.IdAllocator;

pub const ConnectError = error{
    InvalidWaylandSocket,
    NoXdgRuntimeDir,
    NameTooLong,
} || posix.ConnectError || posix.SocketError;

/// Describes the various pieces of information that can be used to connect to a wayland server.
/// This can also be used to debug failing connections, as it implements `format` and can provide
/// a readable display of what information it was using to connect.
pub const ConnectInfo = union(enum) {
    /// A raw socket file descriptor, already connected.
    sock: posix.fd_t,
    /// An endpoint name to be concatenated with `$XDG_RUNTIME_DIR`.
    name: []const u8,
    /// An absolute path to the socket.
    path: []const u8,
    /// Nothing cound be found in the environment,
    /// so try `$XDG_RUNTIME_DIR/wayland-0` as a last resort.
    fallback: void,

    /// Attempt to discover connection information in the process environment
    /// using `$WAYLAND_SOCKET` (**IMPORTANT: see README**) and `$WAYLAND_DISPLAY`,
    /// in conjunction with `$XDG_RUNTIME_DIR`
    pub fn getDefault() ConnectInfo {
        // First try to get WAYLAND_SOCKET environment variable and parse it as a file descriptor.
        if (posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            if (std.fmt.parseInt(posix.fd_t, wayland_socket, 10)) |raw_fd| {
                return .{ .sock = raw_fd };
            } else |_| {} // If parsing fails, ignore it and continue to next strategy
        }

        // Try to find WAYLAND_DISPLAY in environment.
        // If it is an absolute path, return it as .path, otherwise as .name
        if (posix.getenv("WAYLAND_DISPLAY")) |wayland_display| {
            if (std.fs.path.isAbsolute(wayland_display))
                return .{ .path = wayland_display }
            else
                return .{ .name = wayland_display };
        }

        // Nothing could be found, so hope for the best with XDG_RUNTIME_DIR/wayland-0
        return .fallback;
    }

    /// Initialize a `ConnectInfo` by passing an already-connected file descriptor as `socket`.
    pub fn initSocket(socket: posix.fd_t) ConnectInfo {
        return .{ .sock = socket };
    }

    /// Initialize a `ConnectInfo` using a specific socket endpoint name.
    pub fn initName(name: []const u8) ConnectInfo {
        return .{ .name = name };
    }

    /// Initialize a `ConnectInfo` using a specific absolute path.
    pub fn initPath(path: []const u8) ConnectInfo {
        return .{ .path = path };
    }

    /// Returns an established `Connection` based on `self`.
    pub fn connect(
        self: ConnectInfo,
        ida: IdAllocator,
        buffers: *Buffers,
    ) ConnectError!Connection {
        const handle = conn: switch (self) {
            .sock => |fd| fd: {
                // Slightly dirty (maybe temporary) code to confirm that fd is a valid fd
                // and is a socket.
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
                // When connecting to an endpoint, we need XDG_RUNTIME_DIR
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

    /// Format connect info to a writer for logging and/or debugging.
    pub fn format(self: ConnectInfo, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .sock => |sock| try writer.print("socket fd '{d}'", .{sock}),
            .name => |name| try writer.print("socket endpoint name '{s}'", .{name}),
            .path => |path| try writer.print("socket absolute path '{s}'", .{path}),
            .fallback => try writer.writeAll("fallback ($XDG_RUNTIME_DIR/wayland-0)"),
        }
    }
};
