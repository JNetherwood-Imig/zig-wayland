const std = @import("std");

/// Represents the location or socket of a Wayland server.
pub const Address = union(enum) {
    sock: std.posix.fd_t,
    path: [std.Io.net.UnixAddress.max_len:0]u8,

    pub const Error = error{
        /// `XDG_RUNTIME_DIR` does not exist in the process environment.
        NoXdgRuntimeDir,
        /// The path acquired from `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` overflows `std.Io.net.UnixAddress.max_len`.
        PathTooLong,
        /// The fd provided either manually or by `WAYLAND_SOCKET` either does not exist or does not refer to a socket.
        InvalidFd,
    };

    // FIXME: Should we check the validity of the returned address here rather than in Connection.init?
    /// Uses the environment to try to find the parent server's socket.
    ///
    /// If the `WAYLAND_SOCKET` environment variable exists and is set to an integer,
    /// it is interpreted as an open file descriptor and removed from the map.
    ///
    /// Otherwise, a path will be built using `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY`. If `XDG_RUNTIME_DIR` does not exist,
    /// `Error.NoXdgRuntimeDir` will be returned. If `WAYLAND_DISPLAY` exists, then `XDG_RUNTIME_DIR/WAYLAND_DISPLAY` will be used.
    /// If `WAYLAND_DISPLAY` does not exist, `XDG_RUNTIME_DIR/wayland-0` will serve as a final fallback.
    pub fn default(io: std.Io, env: *std.process.Environ.Map) Error!Address {
        if (env.get("WAYLAND_SOCKET")) |sock_str| {
            if (std.fmt.parseInt(std.posix.fd_t, sock_str, 10)) |sock| {
                _ = env.swapRemove("WAYLAND_SOCKET");
                return .fromFd(sock);
            } else |_| {}
        }

        const wayland_display = env.get("WAYLAND_DISPLAY") orelse "wayland-0";

        return .fromEndpoint(env, wayland_display);
    }

    // FIXME: Should we validate the fd here?
    /// Directly initializes an Address using `sock`
    pub fn fromFd(io: std.Io, sock: std.posix.fd_t) Error!Address {
        return Address{
            return .{ .sock = sock },
        };
    }

    // FIXME
    /// Concatenates `endpoint` with `XDG_RUNTIME_DIR` to make a path.
    pub fn fromEndpoint(io: std.Io, env: *const std.process.Environ.Map, endpoint: []const u8) Error!Address {
        const xdg_runtime_dir = env.get("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;
        var self = Address{ .path = @splat(0) };
        _ = std.fmt.bufPrintSentinel(&self.info.path, "{s}/{s}", .{ xdg_runtime_dir, endpoint }, 0) catch
            return error.PathTooLong;
        return self;
    }

    // FIXME
    /// Directly initializes with `path`.
    /// Checks if `path.len` exceeds `std.Io.net.UnixAddress.max_len`.
    pub fn fromAbsolutePath(io: std.Io, path: []const u8) Error!Address {
        if (path.len > std.Io.net.UnixAddress.max_len) return error.PathTooLong;
        var self = Address{
            .strategy = .path,
            .info = .{ .path = @splat(0) },
        };
        @memcpy(self.info.path[0..path.len], path);
        return self;
    }

    /// Provides formatted printing, useful for debugging connect-time errors.
    pub fn format(self: Address, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self.strategy) {
            .sock => try w.print("socket fd '{d}'", .{self.info.sock}),
            .name => {
                const idx = if (std.mem.findScalarLast(u8, &self.info.path, '/')) |i| i + 1 else 0;
                const endpoint = std.mem.sliceTo(self.info.path[idx..], 0);
                try w.print("endpoint '{s}'", .{endpoint});
            },
            .path => {
                const path = std.mem.sliceTo(&self.info.path, 0);
                try w.print("absolute path '{s}'", .{path});
            },
        }
    }
};
