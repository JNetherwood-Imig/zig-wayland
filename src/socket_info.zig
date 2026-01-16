const std = @import("std");
const log = std.log.scoped(.wayland);
const sys = std.posix.system;
const Server = @import("Server.zig");
const Connection = @import("Connection.zig");
const Init = std.process.Init;

/// Describes the various pieces of information that can be used to connect to a wayland server.
/// This can also be used to debug failing connections, as it implements `format` and can provide
/// a readable display of what information it was using to connect.
pub const SocketInfo = union(enum) {
    /// Defer socket resolution until it is needed (either by calling `connect` or `listen`)
    /// and try to automatically detect or create a socket using environment variables.
    auto: void,
    /// An open file descriptor, already configured appropriately for either client or server.
    sock: i32,
    /// An endpoint name to be concatenated with `$XDG_RUNTIME_DIR`.
    name: [std.Io.net.UnixAddress.max_len]u8,
    /// An absolute path to the socket.
    path: [std.Io.net.UnixAddress.max_len]u8,

    /// Initialize with an already-connected file descriptor.
    /// When the resulting `Connection` or `Server` is deinitialized,
    /// `socket` will be closed, but if it exists in the filesystem, it will not be unlinked.
    pub fn initSock(sock: i32) SocketInfo {
        return .{ .sock = sock };
    }

    /// Initialize using a specific socket endpoint name.
    /// The given `name` will be concatenated with `$XDG_RUNTIME_DIR` to make the socket path.
    pub fn initName(name: []const u8) error{NameTooLong}!SocketInfo {
        if (name.len > 108) return error.NameTooLong;
        var self: SocketInfo = .{ .name = @splat(0) };
        @memcpy(self.name[0..name.len], name);
        return self;
    }

    /// Initialize using a specific absolute path.
    pub fn initPath(path: []const u8) error{PathTooLong}!SocketInfo {
        if (path.len > 108) return error.PathTooLong;
        var self: SocketInfo = .{ .path = @splat(0) };
        @memcpy(self.path[0..path.len], path);
        return self;
    }

    pub const ConnectError = ConnectAutoError;

    /// Connect to the socket described in `self`.
    /// If `self` is `.auto`, then use environment variables to detect the connection target,
    /// and store the target in `self` for debugging if connecting fails.
    pub fn connect(self: *SocketInfo, init: Init, io: std.Io) ConnectError!Connection {
        return switch (self.*) {
            .auto => self.connectAuto(init, io),
            .sock => |sock| connectSock(io, sock),
            .name => |name| connectName(init, io, std.mem.sliceTo(&name, 0)),
            .path => |path| connectPath(io, std.mem.sliceTo(&path, 0)),
        };
    }

    pub const ListenError = ListenAutoError || ListenSockError;

    pub fn listen(self: *SocketInfo, init: Init, io: std.Io) ListenError!Server {
        return switch (self.*) {
            .auto => self.listenAuto(init, io),
            .sock => |sock| listenSock(io, sock),
            .name => |name| listenName(init, io, std.mem.sliceTo(&name, 0)),
            .path => |path| listenPath(io, std.mem.sliceTo(&path, 0)),
        };
    }

    const ConnectAutoError = ConnectNameError ||
        ConnectSockError ||
        error{ PathTooLong, NameTooLong };

    fn connectAuto(self: *SocketInfo, init: Init, io: std.Io) ConnectAutoError!Connection {
        if (tryWaylandSocket(init)) |sock| {
            self.* = initSock(sock);
            return connectSock(io, sock);
        }

        const display = init.environ_map.get("WAYLAND_DISPLAY") orelse "wayland-0";
        if (std.Io.Dir.path.isAbsolute(display)) {
            self.* = try initPath(display);
            return connectPath(io, display);
        } else {
            self.* = try initName(display);
            return connectName(init, io, display);
        }
    }

    const ConnectNameError = ConnectPathError || error{NoXdgRuntimeDir};

    fn connectName(init: Init, io: std.Io, name: []const u8) ConnectNameError!Connection {
        const xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;

        var path_buf: [std.Io.net.UnixAddress.max_len]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir, name }) catch
            return error.NameTooLong;

        return connectPath(io, path);
    }

    const ConnectPathError = std.Io.net.UnixAddress.InitError ||
        std.Io.net.UnixAddress.ConnectError;

    fn connectPath(io: std.Io, path: []const u8) ConnectPathError!Connection {
        const addr = try std.Io.net.UnixAddress.init(path);
        const stream = try addr.connect(io);
        return Connection{ .socket = stream.socket };
    }

    const ConnectSockError = std.Io.File.StatError || error{ BadFd, NotASocket };

    fn connectSock(io: std.Io, fd: i32) ConnectSockError!Connection {
        if (!isValidFd(fd)) return error.BadFd;
        const file = std.Io.File{ .handle = fd };
        const stat = try file.stat(io);
        if (stat.kind != .unix_domain_socket) return error.NotASocket;
        return Connection{ .socket = .{
            .handle = fd,
            .address = .{ .ip4 = .loopback(0) },
        } };
    }

    fn tryWaylandSocket(init: Init) ?i32 {
        if (init.environ_map.get("WAYLAND_SOCKET")) |sock_str| {
            if (std.fmt.parseInt(i32, sock_str, 10)) |sock| {
                _ = init.environ_map.swapRemove(sock_str);
                return sock;
            } else |_| {}
        }
        return null;
    }

    /// Ensures that `fd` is a valid fd.
    fn isValidFd(fd: i32) bool {
        const rc = sys.fcntl(fd, sys.F.GETFD, 0);
        return rc != -1;
    }

    const ListenAutoError = ListenNameError ||
        std.Io.File.OpenError ||
        std.Io.Dir.AccessError ||
        error{AllDisplaysInUse};

    fn listenAuto(self: *SocketInfo, init: Init, io: std.Io) ListenAutoError!Server {
        const xdg_runtime_dir_path = init.environ_map.get("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;
        var xdg_runtime_dir = try std.Io.Dir.openDirAbsolute(io, xdg_runtime_dir_path, .{});
        defer xdg_runtime_dir.close(io);

        var name_buf: [12]u8 = undefined;
        const name = for (0..1000) |display_id| {
            const name = std.fmt.bufPrint(&name_buf, "wayland-{d}", .{display_id}) catch
                unreachable;

            xdg_runtime_dir.access(io, name, .{}) catch |err| switch (err) {
                error.FileNotFound => break name,
                else => {},
            };
        } else return error.AllDisplaysInUse;

        self.* = try initName(name);

        return listenName(init, io, name);
    }

    const ListenNameError = ListenPathError || error{NoXdgRuntimeDir};

    fn listenName(init: Init, io: std.Io, name: []const u8) ListenNameError!Server {
        const xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;

        var path_buf: [std.Io.net.UnixAddress.max_len]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir, name }) catch
            return error.NameTooLong;

        return listenPath(io, path);
    }

    const ListenPathError = std.Io.net.UnixAddress.InitError || std.Io.net.UnixAddress.ListenError;

    fn listenPath(io: std.Io, path: []const u8) ListenPathError!Server {
        const addr = try std.Io.net.UnixAddress.init(path);
        const inner = try addr.listen(io, .{});
        var server = Server{ .inner = inner };
        @memcpy(server.path[0..path.len], path);
        return server;
    }

    const ListenSockError = std.Io.File.StatError || error{ BadFd, NotASocket };

    fn listenSock(io: std.Io, fd: i32) ListenSockError!Server {
        if (!isValidFd(fd)) return error.BadFd;
        const file = std.Io.File{ .handle = fd };
        const stat = try file.stat(io);
        if (stat.kind != .unix_domain_socket) return error.NotASocket;
        return Server{ .inner = .{ .socket = .{
            .handle = fd,
            .address = .{ .ip4 = .loopback(0) },
        } } };
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
