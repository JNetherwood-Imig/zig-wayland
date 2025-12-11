const std = @import("std");
const IdAllocator = @import("../IdAllocator.zig");
const posix = std.posix;
const Connection = @import("../Connection.zig");
const ConnectError = Connection.ConnectError;

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
        read_buf: []u8,
        write_buf: []u8,
        fd_read_buf: []posix.fd_t,
        fd_write_buf: []posix.fd_t,
    ) ConnectError!Connection {
        return Connection.connect(self, ida, read_buf, write_buf, fd_read_buf, fd_write_buf);
    }
};
