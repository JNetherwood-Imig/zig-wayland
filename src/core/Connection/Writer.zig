const std = @import("std");
const cmsg = @import("util").cmsg;
const posix = std.posix;

const Writer = @This();

socket: posix.fd_t,
data: Buffer,
fds: Buffer,

pub fn init(socket: posix.fd_t, data_buf: []u8, fd_buf: []posix.fd_t) Writer {
    return .{
        .socket = socket,
        .data = .{
            .buffer = data_buf,
            .end = 0,
        },
        .fds = .{
            .buffer = std.mem.sliceAsBytes(fd_buf),
            .end = 0,
        },
    };
}

pub fn writeData(self: *Writer, data: []const u8) !void {
    var written: usize = 0;
    while (true) {
        written += try self.data.write(data);
        if (written == data.len) break;
        try self.flush();
    }
}

pub fn writeFds(self: *Writer, fds: []const posix.fd_t) !void {
    std.debug.assert(fds.len <= 20);
    const data = std.mem.sliceAsBytes(fds);
    var written: usize = 0;
    while (true) {
        written += try self.fds.write(data);
        if (written == data.len) break;
        try self.flush();
    }
}

pub fn flush(self: *Writer) !void {
    const data = self.data.flush();
    if (data.len == 0) return;

    const iov = [1]posix.iovec_const{.{ .base = data.ptr, .len = data.len }};

    var control: [cmsg.space(20)]u8 align(8) = @splat(0);
    const cmsg_ptr: *cmsg.Header = @ptrCast(&control);
    const cmsg_data = control[@sizeOf(cmsg.Header)..];

    const fds = self.fds.flush();
    const count = fds.len / @sizeOf(posix.fd_t);
    std.debug.assert(count <= 20);
    cmsg_ptr.* = .{ .len = cmsg.length(count) };
    @memcpy(cmsg_data[0..fds.len], fds);

    const msg = posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = if (count > 0) &control else null,
        .controllen = if (count > 0) cmsg_ptr.len else 0,
        .flags = 0,
    };

    _ = try posix.sendmsg(self.socket, &msg, 0);
}

const Buffer = struct {
    buffer: []u8,
    end: usize,

    pub fn write(self: *Buffer, data: []const u8) !usize {
        const written = @min(data.len, self.buffer.len - self.end);
        @memcpy(self.buffer[self.end .. self.end + written], data[0..written]);
        self.end += written;
        return written;
    }

    pub fn flush(self: *Buffer) []const u8 {
        const data = self.buffer[0..self.end];
        self.end = 0;
        return data;
    }
};
