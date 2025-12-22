const std = @import("std");
const cmsg = @import("cmsg.zig");
const wire = @import("../wire.zig");
const posix = std.posix;

const Reader = @This();

/// The `handle` of a `Connection`
socket: posix.fd_t,

/// Backing buffer into which wire data is serialized.
/// Aligned to 4 bytes because the Wayland wire is encoded as 32 bit words.
buf: []align(4) u8,
/// Marks start of unread data in buffer.
start: usize = 0,
/// Marks end of used buffer space.
end: usize = 0,

/// Fd ring buffer backing storage.
fd_buf: []posix.fd_t,
/// Fd ring buffer current index.
fd_start: usize = 0,
/// Fd ring buffer end index.
fd_end: usize = 0,

/// Initialize a `Writer` targeting `socket` backed by `buf` and `fd_buf`.
/// Returns a new `Writer` equivalent to having initialized the parameters manually,
/// except for asserting that the buffer sizes are nonzero.
pub fn init(socket: posix.fd_t, buf: []align(4) u8, fd_buf: []posix.fd_t) Reader {
    std.debug.assert(buf.len > 0 and fd_buf.len > 0);
    return .{
        .socket = socket,
        .buf = buf,
        .fd_buf = fd_buf,
    };
}

/// Returns either a slice of `n` bytes from the buffer, or null if there are less than `n` bytes
/// available.
/// Does not increment the head of the buffer.
pub fn peek(self: *const Reader, n: usize) ?[]const u8 {
    if (self.end - self.start < n) return null;
    return self.buf[self.start..][0..n];
}

/// Increments the head of the buffer `n` bytes.
pub fn discard(self: *Reader, n: usize) void {
    std.debug.assert(self.start + n <= self.end);
    self.start += n;
}

pub fn peekFds(self: *const Reader, n: usize) ?[]const posix.fd_t {
    if (self.fd_end - self.fd_start < n) return null;
    return self.fd_buf[self.fd_start..][0..n];
}

pub fn discardFds(self: *Reader, n: usize) void {
    std.debug.assert(self.fd_start + n <= self.fd_end);
    self.fd_start += n;
}

pub const ReadIncomingError = RecvMsgError || error{ConnectionClosed};

/// Read incoming data and fds.
/// Bytes read from the wire will be buffered in `self.buf`.
/// Fds read from ancillary data will be enqueued in the fd ring buffer.
pub fn readIncoming(self: *Reader) ReadIncomingError!void {
    // Start by shifting leftover bytes to the start of the buffer to make room for incoming data.
    self.shiftToStart();

    // Construct an iovec wrapping the available part of the buffer.
    const available_buf = self.buf[self.end..];
    var iov = [1]posix.iovec{.{ .base = available_buf.ptr, .len = available_buf.len }};

    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 align(8) = @splat(0);
    const controllen = cmsg.length(self.fd_buf.len - self.fd_end);

    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &control,
        .controllen = controllen,
        .flags = 0,
    };

    const read = try recvmsg(self.socket, &msg, 0);

    // If recvmsg returns successfully, but has read no data, that indicates that the other end of
    // the connection was closed.
    if (read == 0) return error.ConnectionClosed;

    self.end += read;

    var header = cmsg.firstHeader(&msg);
    while (header) |h| {
        for (std.mem.bytesAsSlice(posix.fd_t, cmsg.dataConst(h))) |fd| {
            std.debug.assert(self.fd_end < self.fd_buf.len);
            self.fd_buf[self.fd_end] = fd;
            self.fd_end += 1;
        }
        header = cmsg.nextHeader(&msg, h);
    }
}

fn shiftToStart(self: *Reader) void {
    const len = self.end - self.start;
    if (self.start > len)
        @memcpy(self.buf[0..len], self.buf[self.start..self.end])
    else
        @memmove(self.buf[0..len], self.buf[self.start..self.end]);
    self.start = 0;
    self.end = len;

    const fd_len = self.fd_end - self.fd_start;
    if (self.fd_start > fd_len)
        @memcpy(self.fd_buf[0..fd_len], self.fd_buf[self.fd_start..self.fd_end])
    else
        @memmove(self.fd_buf[0..fd_len], self.fd_buf[self.fd_start..self.fd_end]);
    self.fd_start = 0;
    self.fd_end = fd_len;
}

test "peek/discard" {
    var buf: [1024]u8 align(4) = undefined;
    var fd_buf: [16]posix.fd_t = undefined;
    var r: Reader = .init(-1, &buf, &fd_buf);

    // First we have to fake-read some data
    const data = "hello, world!";
    @memcpy(r.buf[r.start..][0..data.len], data);
    r.end += data.len;

    try std.testing.expectEqualSlices(u8, data, r.buf[r.start..r.end]);
    try std.testing.expectEqual(0, r.start);
    try std.testing.expectEqual(data.len, r.end);

    const hello = r.peek(5).?;
    r.discard(hello.len);
    try std.testing.expectEqualSlices(u8, "hello", hello);
    try std.testing.expectEqual(5, r.start);
    try std.testing.expectEqual(data.len, r.end);

    r.shiftToStart();
    try std.testing.expectEqual(0, r.start);
    try std.testing.expectEqual(data.len - 5, r.end);

    r.discard(2);
    try std.testing.expectEqual(2, r.start);
    try std.testing.expectEqual(data.len - 5, r.end);

    const world = r.peek(5).?;
    r.discard(world.len);
    try std.testing.expectEqualSlices(u8, "world", world);
    try std.testing.expectEqual(7, r.start);
    try std.testing.expectEqual(data.len - 5, r.end);
}

// FIXME: This was taken from zig 0.16 std.posix since we don't have it yet,
// but should be removed as soon as 0.16 comes out.
const RecvMsgError = error{
    WouldBlock,
    SystemFdQuotaExceeded,
    ProcessFdQuotaExceeded,
    SystemResources,
    SocketUnconnected,
    MessageOversize,
    BrokenPipe,
    ConnectionResetByPeer,
    NetworkDown,
} || error{Unexpected};

fn recvmsg(sockfd: posix.fd_t, msg: *posix.msghdr, flags: u32) RecvMsgError!usize {
    while (true) {
        const rc = std.os.linux.recvmsg(sockfd, msg, flags);
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .AGAIN => return error.WouldBlock,
            .BADF => unreachable, // always a race condition
            .NFILE => return error.SystemFdQuotaExceeded,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .INTR => continue,
            .FAULT => unreachable, // An invalid user space address was specified for an argument.
            .INVAL => unreachable, // Invalid argument passed.
            .ISCONN => unreachable, // connection-mode socket was connected already but a recipient was specified
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOTCONN => return error.SocketUnconnected,
            .NOTSOCK => unreachable, // The file descriptor sockfd does not refer to a socket.
            .MSGSIZE => return error.MessageOversize,
            .PIPE => return error.BrokenPipe,
            .OPNOTSUPP => unreachable, // Some bit in the flags argument is inappropriate for the socket type.
            .CONNRESET => return error.ConnectionResetByPeer,
            .NETDOWN => return error.NetworkDown,
            else => |err| return posix.unexpectedErrno(err),
        }
    }
}
