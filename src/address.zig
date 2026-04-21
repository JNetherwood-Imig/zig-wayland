const std = @import("std");

/// Represents the location or socket of a Wayland server.
pub const Address = union(enum) {
    sock: std.posix.fd_t,
    path: struct {
        is_from_endpoint: bool,
        data: [std.Io.net.UnixAddress.max_len:0]u8,
    },

    pub const Error = error{
        /// `XDG_RUNTIME_DIR` does not exist in the process environment.
        NoXdgRuntimeDir,
        /// The path acquired from `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` overflows `std.Io.net.UnixAddress.max_len`.
        PathTooLong,
        /// The fd provided either manually or by `WAYLAND_SOCKET` either does not exist or does not refer to a socket.
        InvalidFd,
    };

    /// If the `WAYLAND_SOCKET` environment variable exists and is set to an integer,
    /// it is interpreted as an open file descriptor and removed from the map.
    ///
    /// Otherwise, a path will be built using `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY`. If `XDG_RUNTIME_DIR` does not exist,
    /// `Error.NoXdgRuntimeDir` will be returned. If `WAYLAND_DISPLAY` exists, then `XDG_RUNTIME_DIR/WAYLAND_DISPLAY` will be used.
    /// If `WAYLAND_DISPLAY` does not exist, `XDG_RUNTIME_DIR/wayland-0` will serve as a final fallback.
    pub fn default(env: *std.process.Environ.Map) Error!Address {
        if (env.get("WAYLAND_SOCKET")) |sock_str| {
            if (std.fmt.parseInt(std.posix.fd_t, sock_str, 10)) |sock| {
                _ = env.swapRemove("WAYLAND_SOCKET");
                return .fromFd(sock);
            } else |_| {}
        }

        const wayland_display = env.get("WAYLAND_DISPLAY") orelse "wayland-0";

        return .fromEndpoint(env, wayland_display);
    }

    /// Directly initializes an Address using `sock`
    pub fn fromFd(sock: std.posix.fd_t) Error!Address {
        return Address{ .sock = sock };
    }

    /// Concatenates `endpoint` with `XDG_RUNTIME_DIR` to make a path.
    pub fn fromEndpoint(env: *const std.process.Environ.Map, endpoint: []const u8) Error!Address {
        const xdg_runtime_dir = env.get("XDG_RUNTIME_DIR") orelse
            return error.NoXdgRuntimeDir;
        var self = Address{ .path = .{ .data = @splat(0), .is_from_endpoint = true } };
        _ = std.fmt.bufPrintSentinel(&self.path.data, "{s}/{s}", .{ xdg_runtime_dir, endpoint }, 0) catch
            return error.PathTooLong;
        return self;
    }

    /// Directly initializes with `path`.
    /// Checks if `path.len` exceeds `std.Io.net.UnixAddress.max_len`.
    pub fn fromAbsolutePath(path: []const u8) Error!Address {
        if (path.len > std.Io.net.UnixAddress.max_len) return error.PathTooLong;
        var self = Address{ .path = .{ .data = @splat(0), .is_from_endpoint = false } };
        @memcpy(self.path.data[0..path.len], path);
        return self;
    }

    /// Provides formatted printing, useful for debugging connect-time errors.
    pub fn format(self: Address, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .sock => |s| try w.print("socket fd '{d}'", .{s}),
            .path => |p| if (p.is_from_endpoint) {
                const idx = if (std.mem.findScalarLast(u8, &p.data, '/')) |i| i + 1 else 0;
                const endpoint = std.mem.sliceTo(p.data[idx..], 0);
                try w.print("endpoint '{s}'", .{endpoint});
            } else {
                const path = std.mem.sliceTo(&p.data, 0);
                try w.print("absolute path '{s}'", .{path});
            },
        }
    }
};
