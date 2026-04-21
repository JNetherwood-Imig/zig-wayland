//! Establishes a unix socket for serving Wayland clients.

const std = @import("std");
const S = std.posix.S;

const Connection = @import("Connection.zig");

const max_displays = 100;
const endpoint_max_len = "wayland-99".len;
const lock_suffix = ".lock";

const Server = @This();

inner: std.Io.net.Server,
lock: std.Io.File,
/// Tracks location of socket so that the file can be removed
lock_path: [std.Io.net.UnixAddress.max_len + lock_suffix.len]u8,

pub const InitError = LockDisplayError ||
    std.Io.Dir.OpenError ||
    std.Io.net.UnixAddress.ListenError ||
    error{
        NoXdgRuntimeDir,
        NoDisplaysAvailable,
        NameTooLong,
        NoSpaceLeft,
    };

/// Initializes a server using the process environment.
/// Creates a unix socket and lock file for the next available Wayland display number (up to `wayland-99`).
pub fn init(io: std.Io, env: *const std.process.Environ.Map) InitError!Server {
    const xdg_runtime_dir_path = env.get("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;

    const xdg_runtime_dir = try std.Io.Dir.openDirAbsolute(io, xdg_runtime_dir_path, .{});
    defer xdg_runtime_dir.close(io);

    var lock_name_buf: [endpoint_max_len + lock_suffix.len]u8 = undefined;
    var lock_name: []const u8 = undefined;

    const lock: std.Io.File = for (0..max_displays) |display| {
        lock_name = std.fmt.bufPrint(&lock_name_buf, "wayland-{}" ++ lock_suffix, .{display}) catch unreachable;
        // Succeeds if `XDG_RUNTIME_DIR/wayland-{display}.lock` can be successfully locked with an exclusive lock,
        // and `XDG_RUNTIME_DIR/wayland-{display}` can be removed if it exists.
        break lockDisplay(io, xdg_runtime_dir, lock_name) catch |err| switch (err) {
            error.LockFailed => continue,
            else => |e| return e,
        };
    } else return error.NoDisplaysAvailable;
    errdefer {
        lock.close(io);
        xdg_runtime_dir.deleteFile(io, lock_name) catch {};
    }

    var self = Server{
        .inner = undefined,
        .lock = lock,
        .path = @splat(0),
    };

    const lock_path = try std.fmt.bufPrint(&self.path, "{s}/{s}", .{ xdg_runtime_dir_path, lock_name });
    const endpoint_path = std.mem.cutSuffix(u8, lock_path, lock_suffix).?;
    const addr = try std.Io.net.UnixAddress.init(endpoint_path);
    self.inner = try addr.listen(io, .{});

    return self;
}

/// Close the server's socket fd and lock fd, and remove both files from the filesystem.
pub fn deinit(self: *Server, io: std.Io) void {
    std.Io.Dir.deleteFileAbsolute(io, std.mem.sliceTo(&self.lock_path, 0)) catch {};
    std.Io.Dir.deleteFileAbsolute(io, self.socketPath()) catch {};

    self.lock.close(io);
    self.inner.deinit(io);

    self.* = undefined;
}

/// Get the socket fd.
pub fn getFd(self: *const Server) std.posix.fd_t {
    return self.inner.socket.handle;
}

/// Get the full socket path.
pub fn socketPath(self: *const Server) []const u8 {
    return std.mem.cutSuffix(u8, &self.lock_path, lock_suffix).?;
}

/// Get just the endpoint name.
pub fn endpoint(self: *const Server) []const u8 {
    const path = self.socketPath();
    const idx = if (std.mem.findScalarLast(u8, path, '/')) |idx| idx + 1 else 0;
    return path[idx..];
}

pub const AcceptError = std.Io.net.Server.AcceptError || error{OutOfMemory};

/// Accept an incoming Wayland client and return an initialized `Connection`.
pub fn accept(self: *Server, io: std.Io, gpa: std.mem.Allocator) AcceptError!Connection {
    const stream = try self.inner.accept(io);
    return Connection.fromStream(io, gpa, stream, .server);
}

const LockDisplayError = std.Io.File.OpenError ||
    std.Io.Dir.DeleteFileError;

fn lockDisplay(io: std.Io, xdg_runtime_dir: std.Io.Dir, name: []const u8) !std.Io.File {
    const lock_file = try xdg_runtime_dir.createFile(io, name, .{
        .read = true,
        .permissions = .fromMode(S.IRUSR | S.IWUSR | S.IRGRP | S.IWGRP),
        .lock_nonblocking = true,
        .lock = .exclusive,
    });
    errdefer lock_file.close(io);

    const endpoint_name = std.mem.cutSuffix(u8, name, lock_suffix).?;
    if (xdg_runtime_dir.access(io, endpoint_name, .{})) |_| {
        xdg_runtime_dir.deleteFile(io, endpoint_name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return e,
        };
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    }

    return lock_file;
}
