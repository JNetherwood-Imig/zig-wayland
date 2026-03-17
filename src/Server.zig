//! Simple listener to accept Wayland client connections.

const std = @import("std");
const S = std.posix.S;

const Connection = @import("Connection.zig");

const max_displays = 100;

const Server = @This();

inner: std.Io.net.Server,
lock: std.Io.File,
path: [std.Io.net.UnixAddress.max_len:0]u8,

pub const InitError = LockDisplayError ||
    std.Io.Dir.OpenError ||
    std.Io.net.UnixAddress.ListenError ||
    error{
        NoXdgRuntimeDir,
        NoDisplaysAvailable,
        NameTooLong,
        NoSpaceLeft,
    };

pub fn init(args: std.process.Init, io: std.Io) InitError!Server {
    const xdg_runtime_dir_path = args.environ_map.get("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;

    const xdg_runtime_dir = try std.Io.Dir.openDirAbsolute(io, xdg_runtime_dir_path, .{});
    defer xdg_runtime_dir.close(io);

    var endpoint_buf: [12]u8 = undefined;
    var endpoint_name: []const u8 = undefined;

    const lock: std.Io.File = for (0..max_displays) |display| {
        endpoint_name = std.fmt.bufPrint(&endpoint_buf, "wayland-{}", .{display}) catch unreachable;
        break lockDisplay(io, xdg_runtime_dir, endpoint_name) catch |err| switch (err) {
            error.LockFailed => continue,
            else => |e| return e,
        };
    } else return error.NoDisplaysAvailable;
    errdefer lock.close(io);

    var path_buf: [std.Io.net.UnixAddress.max_len]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir_path, endpoint_name });
    const addr = try std.Io.net.UnixAddress.init(path);

    const server = try addr.listen(io, .{});

    var self = Server{
        .inner = server,
        .lock = lock,
        .path = @splat(0),
    };
    @memcpy(self.path[0..path.len], path);

    return self;
}

pub fn deinit(self: *Server, io: std.Io) void {
    const path = std.mem.sliceTo(&self.path, 0);
    var lock_buf: [std.Io.net.UnixAddress.max_len]u8 = undefined;
    const lock_path = std.fmt.bufPrint(&lock_buf, "{s}.lock", .{path}) catch unreachable;

    std.Io.Dir.deleteFileAbsolute(io, path) catch {};
    std.Io.Dir.deleteFileAbsolute(io, lock_path) catch {};

    self.lock.close(io);
    self.inner.socket.close(io);
}

pub inline fn getFd(self: *const Server) std.posix.fd_t {
    return self.inner.socket.handle;
}

pub inline fn socketPath(self: *const Server) []const u8 {
    return std.mem.sliceTo(&self.path, 0);
}

pub inline fn endpoint(self: *const Server) []const u8 {
    const path = self.socketPath();
    const idx = if (std.mem.findScalarLast(u8, path, '/')) |idx| idx + 1 else 0;
    return path[idx..];
}

pub const AcceptError = std.Io.net.Server.AcceptError || error{OutOfMemory};

pub fn accept(self: *Server, io: std.Io, gpa: std.mem.Allocator) AcceptError!Connection {
    const stream = try self.inner.accept(io);
    return Connection.fromStream(io, gpa, stream, .server);
}

const LockDisplayError = std.Io.File.OpenError ||
    std.Io.File.LockError ||
    std.Io.File.StatError ||
    error{LockFailed};

fn lockDisplay(io: std.Io, xdg_runtime_dir: std.Io.Dir, endpoint_name: []const u8) !std.Io.File {
    var lock_buf: [15]u8 = undefined;
    const lock = std.fmt.bufPrint(&lock_buf, "{s}.lock", .{endpoint_name}) catch unreachable;

    const lock_file = try xdg_runtime_dir.createFile(io, lock, .{
        .read = true,
        .permissions = .fromMode(S.IRUSR | S.IWUSR | S.IRGRP | S.IWGRP),
        .lock_nonblocking = true,
    });
    errdefer lock_file.close(io);

    if (!try lock_file.tryLock(io, .exclusive)) return error.LockFailed;

    if (xdg_runtime_dir.statFile(io, endpoint_name, .{ .follow_symlinks = false })) |stat| {
        const mode = stat.permissions.toMode();
        if (mode & S.IWUSR == S.IWUSR or
            mode & S.IWGRP == S.IWGRP)
            xdg_runtime_dir.deleteFile(io, endpoint_name) catch {};
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    }

    return lock_file;
}
