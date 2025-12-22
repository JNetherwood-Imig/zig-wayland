const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const log = std.log.scoped(.wayland);
const Connection = @import("Connection.zig");
const Server = @import("Server.zig");
const IdAllocator = @import("IdAllocator.zig");

/// Describes the various pieces of information that can be used to connect to a wayland server.
/// This can also be used to debug failing connections, as it implements `format` and can provide
/// a readable display of what information it was using to connect.
pub const SocketInfo = union(enum) {
    /// Defer socket resolution until it is needed (either by calling `connect` or `listen`)
    /// and try to automatically detect or create a socket using environment variables.
    auto: void,
    /// An open file descriptor, already configured appropriately for either client or server.
    sock: posix.fd_t,
    /// An endpoint name to be concatenated with `$XDG_RUNTIME_DIR`.
    name: [108]u8,
    /// An absolute path to the socket.
    path: [108]u8,

    /// Initialize a `ConnectInfo` by passing an already-connected file descriptor as `socket`.
    pub fn initSocket(socket: posix.fd_t) SocketInfo {
        return .{ .sock = socket };
    }

    /// Initialize a `ConnectInfo` using a specific socket endpoint name.
    pub fn initName(name: []const u8) !SocketInfo {
        if (name.len > 108) return error.NameTooLong;
        var self: SocketInfo = .{ .name = @splat(0) };
        @memcpy(self.name[0..name.len], name);
        return self;
    }

    /// Initialize a `ConnectInfo` using a specific absolute path.
    pub fn initPath(path: []const u8) !SocketInfo {
        if (path.len > 108) return error.pathTooLong;
        var self: SocketInfo = .{ .path = @splat(0) };
        @memcpy(self.path[0..path.len], path);
        return self;
    }

    pub const ConnectError = ConnectAutoError;

    pub fn connect(self: *SocketInfo, ida: IdAllocator, buffers: *Connection.Buffers) !Connection {
        return switch (self.*) {
            .auto => self.connectAuto(ida, buffers),
            .sock => |sock| connectSock(sock, ida, buffers),
            .name => |name| connectName(std.mem.sliceTo(&name, 0), ida, buffers),
            .path => |path| connectPath(std.mem.sliceTo(&path, 0), ida, buffers),
        };
    }

    const ConnectAutoError = ValidateFdError || ConnectNameError;

    fn connectAuto(
        self: *SocketInfo,
        ida: IdAllocator,
        buffers: *Connection.Buffers,
    ) ConnectAutoError!Connection {
        if (tryWaylandSocket()) |wayland_socket| {
            self.* = .{ .sock = wayland_socket };
            try validateFd(wayland_socket);
            return connectSock(wayland_socket, ida, buffers);
        }

        const display = posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
        if (std.fs.path.isAbsolute(display)) {
            self.* = initPath(display) catch unreachable;
            return connectPath(display, ida, buffers);
        } else {
            self.* = initName(display) catch unreachable;
            return connectName(display, ida, buffers);
        }
    }

    const ConnectNameError = ConnectPathError || error{NoXdgRuntimeDir};

    fn connectName(name: []const u8, ida: IdAllocator, buffers: *Connection.Buffers) !Connection {
        const xdg_runtime_dir = posix.getenv("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;

        var path_buf: [posix.PATH_MAX]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir, name }) catch
            return error.NameTooLong;

        return connectPath(path, ida, buffers);
    }

    const ConnectPathError = posix.SocketError || posix.ConnectError || error{NameTooLong};

    fn connectPath(
        path: []const u8,
        ida: IdAllocator,
        buffers: *Connection.Buffers,
    ) ConnectPathError!Connection {
        const stream = try std.net.connectUnixSocket(path);
        const fd = stream.handle;
        return connectSock(fd, ida, buffers);
    }

    fn connectSock(fd: posix.fd_t, ida: IdAllocator, buffers: *Connection.Buffers) Connection {
        return .init(fd, ida, buffers);
    }

    fn tryWaylandSocket() ?posix.fd_t {
        if (posix.getenv("WAYLAND_SOCKET")) |wayland_socket| {
            if (std.fmt.parseInt(posix.fd_t, wayland_socket, 10)) |raw_fd| {
                unsetenv(wayland_socket);
                return raw_fd;
            } else |_| {}
        }
        return null;
    }

    const ValidateFdError = error{
        BadFd,
        StatFailed,
        NotASocket,
    };

    fn validateFd(fd: posix.fd_t) ValidateFdError!void {
        const rc = std.os.linux.fcntl(fd, posix.F.GETFD, 0);
        switch (posix.errno(rc)) {
            .SUCCESS => {},
            else => return error.BadFd,
        }

        const stat = posix.fstat(fd) catch return error.StatFailed;
        if (!posix.S.ISSOCK(stat.mode)) return error.NotASocket;
    }

    pub const ListenError = ListenAutoError;

    pub fn listen(self: *SocketInfo) ListenError!Server {
        return switch (self.*) {
            .auto => self.listenAuto(),
            .sock => |sock| listenSock(sock),
            .name => |name| listenName(std.mem.sliceTo(&name, 0)),
            .path => |path| listenPath(std.mem.sliceTo(&path, 0)),
        };
    }

    const ListenAutoError = ListenNameError ||
        std.fs.File.OpenError ||
        std.fs.Dir.AccessError ||
        error{DisplaysInUse};

    fn listenAuto(self: *SocketInfo) ListenAutoError!Server {
        var xdg_runtime_dir = dir: {
            const path = posix.getenv("XDG_RUNTIME_DIR") orelse
                return error.NoXdgRuntimeDir;
            break :dir try std.fs.openDirAbsolute(path, .{});
        };
        defer xdg_runtime_dir.close();

        var name_buf: [12]u8 = undefined;
        const name = for (0..1000) |display_id| {
            const name = std.fmt.bufPrint(&name_buf, "wayland-{d}", .{display_id}) catch
                unreachable;

            xdg_runtime_dir.access(name, .{}) catch |err| switch (err) {
                error.FileNotFound => break name,
                else => {},
            };
        } else return error.DisplaysInUse;

        self.* = initName(name) catch unreachable;

        return listenName(name);
    }

    const ListenNameError = ListenPathError || error{NoXdgRuntimeDir};

    fn listenName(name: []const u8) ListenNameError!Server {
        const xdg_runtime_dir = posix.getenv("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;

        var path_buf: [posix.PATH_MAX]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir, name }) catch
            return error.NameTooLong;

        return listenPath(path);
    }

    const ListenPathError = std.net.Address.ListenError || error{NameTooLong};

    fn listenPath(path: []const u8) ListenPathError!Server {
        const addr = try std.net.Address.initUnix(path);
        const server = try addr.listen(.{ .force_nonblocking = true });
        const fd = server.stream.handle;
        return Server{ .handle = fd, .addr = addr };
    }

    fn listenSock(fd: posix.fd_t) Server {
        return .{ .handle = fd, .addr = null };
    }

    /// Implement format function for std.Io.Writer
    pub fn format(self: SocketInfo, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .auto => try writer.writeAll("(unresolved)"),
            .sock => |sock| try writer.print("fd '{d}'", .{sock}),
            .name => |name| try writer.print("endpoint '{s}'", .{name}),
            .path => |path| try writer.print("absolute path '{s}'", .{path}),
        }
    }
};

const c = if (builtin.link_libc) struct {
    pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
} else struct {};

fn unsetenv(name: [:0]const u8) void {
    if (builtin.link_libc) {
        _ = c.unsetenv(name.ptr);
        return;
    }

    log.warn("Globally unsetting environment variables does not work without linking libc.", .{});
    log.warn("Leaking WAYLAND_SOCKET can have consequences if spawning child processes.", .{});
    log.warn("If there is any chance of spawning child wayland clients, " ++
        "it is strongly reccommended to link with libc.", .{});
}
