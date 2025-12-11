const std = @import("std");
const posix = std.posix;
const log = std.log.scoped(.denali_core_connection);

const wire = @import("wire.zig");
const Fd = @import("Fd.zig");

const Connection = @This();

handle: Fd,

pub fn initFd(fd: Fd) !Connection {
    log.debug("Using socket fd: {any}", .{fd});
    return .{ .handle = fd };
}

pub fn initPath(path: []const u8) !Connection {
    var path_buf = [_]u8{0} ** 108;
    const final_path = if (std.fs.path.isAbsolute(path)) path else path: {
        const xdg_runtime_dir = posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
        break :path std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir, path }) catch return error.NameTooLong;
    };
    log.debug("Using socket path: {s}", .{path});
    return connectToPath(final_path);
}

pub fn deinit(self: *const Connection) void {
    self.handle.deinit();
    log.debug("Connection closed.", .{});
}

pub fn sendMessage(self: *const Connection, message: wire.Message) !void {
    const msg = posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = @ptrCast(&.{message.dataIovecConst()}),
        .iovlen = 1,
        .control = message.ancillaryDataConst(),
        .controllen = message.ancillaryDataLen(),
        .flags = 0,
    };
    _ = try posix.sendmsg(self.handle.raw, &msg, 0);
}

pub fn receiveMessage(self: *const Connection) !wire.Message {
    var message: wire.Message = .empty;
    _ = try std.posix.read(self.handle.raw, std.mem.asBytes(message.header()));
    var iov = [_]posix.iovec{message.dataIovec()};
    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = message.ancillaryData(),
        .controllen = message.ancillaryDataLen(),
        .flags = 0,
    };
    return switch (posix.errno(std.os.linux.recvmsg(self.handle.raw, &msg, 0))) {
        .SUCCESS => message,
        else => error.ReadFailed,
    };
}

fn connectToPath(path: []const u8) !Connection {
    const fd = try posix.socket(
        posix.AF.UNIX,
        posix.SOCK.STREAM | posix.SOCK.CLOEXEC,
        0,
    );
    errdefer posix.close(fd);
    var addr = try std.net.Address.initUnix(path);
    try posix.connect(fd, &addr.any, addr.getOsSockLen());
    return .{ .handle = Fd{ .raw = fd } };
}

test "init" {
    _ = try Connection.initFd(.fromStdFile(.stdout()));
    try std.testing.expectError(error.FileNotFound, Connection.initPath("/path/that/does/not/exist"));
}

test "send message" {
    const Proxy = @import("Proxy.zig");
    const conn = try Connection.initPath("/run/user/1000/wayland-1");
    try conn.sendMessage(try .init(1, 1, .{Proxy{ .id = 2, .version = 1 }}));
    const msg = try conn.receiveMessage();
    std.debug.print("{any}", .{msg});
}
