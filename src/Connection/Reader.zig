//! FIX: rewrite once I rewrite the ring buffer.

const std = @import("std");
const cmsg = @import("cmsg.zig");
const wire = @import("../wire.zig");
const posix = std.posix;
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

const Reader = @This();

socket: posix.fd_t,
data: RingBuffer(u8),
fds: RingBuffer(posix.fd_t),

pub fn init(socket: posix.fd_t, data_buf: []u8, fd_buf: []posix.fd_t) Reader {
    return .{
        .socket = socket,
        .data = .init(data_buf),
        .fds = .init(fd_buf),
    };
}

pub const ReadIncomingError = RecvMsgError || error{ConnectionClosed};

pub fn readIncoming(self: *Reader) ReadIncomingError!void {
    var buf: [4096]u8 = undefined;
    var iov = [1]posix.iovec{.{ .base = &buf, .len = buf.len }};
    var control: [cmsg.space(20)]u8 align(8) = @splat(0);
    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = &control,
        .controllen = control.len,
        .flags = 0,
    };
    const read = try recvmsg(self.socket, &msg, 0);
    if (read == 0) return error.ConnectionClosed;
    std.debug.assert(self.data.putMany(buf[0..read]) == read);
    var header = cmsg.firstHeader(&msg);
    while (header) |h| {
        const data = cmsg.dataConst(h);
        const fds = std.mem.bytesAsSlice(posix.fd_t, data);
        std.debug.assert(self.fds.putMany(@alignCast(fds)) == fds.len);
        header = cmsg.nextHeader(&msg, h);
    }
}

pub fn nextHeader(self: *Reader) ?wire.Header {
    if (self.data.used() < @sizeOf(wire.Header)) return null;
    var buf: [@sizeOf(wire.Header)]u8 = undefined;
    std.debug.assert(self.data.takeMany(&buf) == buf.len);
    return std.mem.bytesToValue(wire.Header, &buf);
}

pub fn nextFd(self: *Reader) ?posix.fd_t {
    return self.fds.take();
}

pub fn getData(self: *Reader, buf: []u8) usize {
    return self.data.takeMany(buf);
}

// FIX
// Taken from zig 0.16 std.posix since we don't have it yet
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
