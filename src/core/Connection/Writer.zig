const std = @import("std");
const cmsg = @import("../cmsg.zig");
const posix = std.posix;
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

const Writer = @This();

socket: posix.fd_t,
data: RingBuffer(u8),
fds: RingBuffer(posix.fd_t),

pub fn init(socket: posix.fd_t, data_buf: []u8, fd_buf: []posix.fd_t) Writer {
    return .{
        .socket = socket,
        .data = .init(data_buf),
        .fds = .init(fd_buf),
    };
}

pub fn writeData(self: *Writer, data: []const u8) !void {
    var written: usize = 0;
    while (true) {
        written += self.data.putMany(data);
        if (written == data.len) break;
        try self.flush();
    }
}

pub fn writeFds(self: *Writer, fds: []const posix.fd_t) !void {
    std.debug.assert(fds.len <= 20);
    var written: usize = 0;
    while (true) {
        written += self.fds.putMany(fds);
        if (written == fds.len) break;
        try self.flush();
    }
}

pub fn flush(self: *Writer) !void {
    const iov = self.data.toIovecConst();

    var control: [cmsg.space(20)]u8 align(8) = @splat(0);
    const cmsg_ptr: *cmsg.Header = @ptrCast(&control);
    const cmsg_data = control[@sizeOf(cmsg.Header)..];

    const count = self.fds.takeMany(std.mem.bytesAsSlice(posix.fd_t, cmsg_data));
    std.debug.assert(count <= 20);
    cmsg_ptr.* = .{ .len = cmsg.length(count) };

    const msg = posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = if (count > 0) &control else null,
        .controllen = if (count > 0) cmsg_ptr.len else 0,
        .flags = 0,
    };

    _ = try posix.sendmsg(self.socket, &msg, 0);
}
