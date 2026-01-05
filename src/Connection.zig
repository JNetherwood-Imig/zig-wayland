//! Buffered socket abstraction for exchanging messages according to the wayland wire format.
//! See `wire.zig` for serialization and deserialization information.

const std = @import("std");
const wire = @import("wire.zig");
const cmsg = @import("cmsg.zig");
const IdAllocator = @import("IdAllocator.zig");
const posix = std.posix;
const control_buf_len = cmsg.space(wire.libwayland_max_message_args);
const default_head_bytes = std.mem.toBytes(cmsg.Header{ .len = cmsg.length(0) });

const Connection = @This();

handle: posix.fd_t,
ida: IdAllocator,

read_buf: [4096]u8 align(4) = @splat(0),
write_buf: [4096]u8 align(4) = @splat(0),
fd_read_buf: [20]posix.fd_t = @splat(-1),
control_buf: [control_buf_len]u8 align(8) = default_head_bytes ++ @as([80]u8, @splat(0)),

reader_start: usize = 0,
reader_end: usize = 0,
reader_fd_start: usize = 0,
reader_fd_end: usize = 0,

writer_end: usize = 0,

/// Close the underlying connection file descriptor.
pub fn deinit(self: *Connection) void {
    posix.close(self.handle);
    self.* = undefined;
}

pub const PollEventsError = posix.PollError || error{Timeout};

/// Polls for events, returning `error.TimedOut` if nothing is received after `timeout` ms.
/// If `timeout` is -1, it will poll indefinately.
pub fn pollEvents(self: *Connection, timeout: i32) PollEventsError!void {
    var pfd = posix.pollfd{
        .fd = self.handle,
        .events = posix.POLL.IN,
        .revents = 0,
    };

    // If we get no signaled fds before timing out, return false
    if (try posix.poll((&pfd)[0..1], timeout) == 0)
        return error.Timeout;
}

/// Returns either a slice of `n` bytes from the buffer, or null if there are less than `n` bytes
/// available.
/// Does not advance the head of the read buffer.
pub fn peek(self: *const Connection, n: usize) ?[]const u8 {
    if (self.reader_end - self.reader_start < n) return null;
    return self.read_buf[self.reader_start..][0..n];
}

/// Returns the next 8 bytes from the buffer, interpreted as a `wire.Header`.
/// This function does not discard what it reads, so subsequent calls will return the same data
/// until `dsicard` is called.
pub fn peekHeader(self: *const Connection) ?wire.Header {
    if (self.peek(@sizeOf(wire.Header))) |buf| {
        return std.mem.bytesToValue(wire.Header, buf);
    }

    return null;
}

/// Advances the head of the buffer `n` bytes.
pub fn discard(self: *Connection, n: usize) void {
    std.debug.assert(self.reader_start + n <= self.reader_end);
    self.reader_start += n;
}

/// Returns either a slice of `n` fds from the fd buffer, or null if there are less than `n` fds
/// available.
/// Does not advance the head of the fd buffer.
pub fn peekFds(self: *const Connection, n: usize) ?[]const posix.fd_t {
    if (n > self.reader_fd_end - self.reader_fd_start) return null;
    return self.fd_read_buf[self.reader_fd_start..][0..n];
}

/// Advances the head of the fd buffer `n` fds.
pub fn discardFds(self: *Connection, n: usize) void {
    std.debug.assert(n <= self.reader_fd_end - self.reader_fd_start);
    self.reader_fd_start += n;
}

pub const ReadIncomingError = RecvMsgError || error{ConnectionClosed};

/// Read and buffer incoming data and fds.
pub fn readIncoming(self: *Connection) ReadIncomingError!void {
    // Start by shifting leftover bytes to the start of the buffer to make room for incoming data.
    self.resetReader();

    // Construct an iovec wrapping the available part of the buffer.
    const available_buf = self.read_buf[self.reader_end..];
    var iov = [1]posix.iovec{.{ .base = available_buf.ptr, .len = available_buf.len }};

    var control: [control_buf_len]u8 align(8) = @splat(0);
    const controllen = cmsg.length(self.fd_read_buf.len - self.reader_fd_end);

    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &control,
        .controllen = controllen,
        .flags = 0,
    };

    const read = try recvmsg(self.handle, &msg, 0);

    // If recvmsg returns successfully, but has read no data, that indicates that the other end of
    // the connection was closed.
    if (read == 0) return error.ConnectionClosed;

    self.reader_end += read;

    var header = cmsg.firstHeader(&msg);
    while (header) |h| {
        for (std.mem.bytesAsSlice(posix.fd_t, cmsg.dataConst(h))) |fd| {
            std.debug.assert(self.reader_fd_end < self.fd_read_buf.len);
            self.fd_read_buf[self.reader_fd_end] = fd;
            self.reader_fd_end += 1;
        }
        header = cmsg.nextHeader(&msg, h);
    }
}

fn resetReader(self: *Connection) void {
    const len = self.reader_end - self.reader_start;
    if (len > 0) {
        if (self.reader_start > len)
            @memcpy(self.read_buf[0..len], self.read_buf[self.reader_start..][0..len])
        else
            @memmove(self.read_buf[0..len], self.read_buf[self.reader_start..][0..len]);
    }
    self.reader_start = 0;
    self.reader_end = len;

    const fd_len = self.reader_fd_end - self.reader_fd_start;
    if (fd_len > 0) {
        if (self.reader_fd_start > fd_len)
            @memcpy(self.fd_read_buf[0..fd_len], self.fd_read_buf[self.reader_fd_start..][0..fd_len])
        else
            @memmove(self.fd_read_buf[0..fd_len], self.fd_read_buf[self.reader_fd_start..][0..fd_len]);
    }
    self.reader_fd_start = 0;
    self.reader_fd_end = fd_len;
}

pub const PutError = FlushError || error{MessageTooLong};

/// Write all of `bytes` to the underlying buffer, flushing as many times as is necessary
/// to ensure that all bytes are sent.
///
/// See `flush` for error information.
pub fn put(self: *Connection, bytes: []const u8) PutError!void {
    if (bytes.len > wire.libwayland_max_message_size)
        return error.MessageTooLong;

    var written: usize = 0;
    while (written < bytes.len) {
        if (self.writer_end == self.write_buf.len) try self.flush();
        const len = @min(bytes.len, self.write_buf.len - self.writer_end);
        @memcpy(self.write_buf[self.writer_end..][0..len], bytes[written..][0..len]);
        self.writer_end += len;
        written += len;
    }
}

pub const PutFdsError = FlushError || error{ TooManyFds, ProcessFdQuotaExceeded, Unexpected };

/// Write all of `fds` to the control buffer, incrementing the cmsg.Header data encoded at the
/// start of the buffer to match. This function will flush the buffers if there is insufficient
/// space to accomodate `fds`.
///
/// See `flush` for error information.
pub fn putFds(self: *Connection, fds: []const posix.fd_t) PutFdsError!void {
    if (fds.len > wire.libwayland_max_message_args)
        return error.TooManyFds;

    for (0..fds.len) |i| {
        const control_len = self.controlHeader().len;
        if (self.control_buf.len - control_len < 4)
            try self.flush();
        const fd = try posix.dup(fds[i]);
        std.mem.bytesAsValue(posix.fd_t, self.control_buf[control_len..][0..4]).* = fd;
        self.controlHeader().len += 4;
    }
}

pub const FlushError = posix.SendMsgError || error{ConnectionClosed};

/// Flush the contents of both the data and fd buffers to the socket.
/// This function blocks if `std.posix.sendmsg` blocks, but this is very unlikely.
///
/// Returns `void` on success.
/// Returns `error.ConnectionClosed` if the send completes, but no bytes were sent,
/// indicating that the other end of the connection has closed.
/// Returns some member of `std.posix.SendMsgError` if the call to sendmsg fails.
pub fn flush(self: *Connection) FlushError!void {
    // We don't have anything to send.
    if (self.writer_end == 0) return;

    const iov = [1]posix.iovec_const{.{ .base = &self.write_buf, .len = self.writer_end }};
    const head = self.controlHeader();
    const control = if (head.len > cmsg.length(0)) &self.control_buf else null;
    const controllen = if (head.len > cmsg.length(0)) head.len else 0;

    const msg = posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = control,
        .controllen = controllen,
        .flags = 0,
    };

    // This is blocking, maybe it shouldn't be?
    const sent = try posix.sendmsg(self.handle, &msg, 0);

    // If sendmsg returns successfully, but has sent no data, that indicates that the other end of
    // the connection was closed.
    if (sent == 0) return error.ConnectionClosed;

    // Reset data buffer end pos and control header len.
    self.resetWriter();
}

fn controlHeader(self: *Connection) *cmsg.Header {
    return std.mem.bytesAsValue(cmsg.Header, self.control_buf[0..@sizeOf(cmsg.Header)]);
}

fn resetWriter(self: *Connection) void {
    const head = self.controlHeader();
    const fds = std.mem.bytesAsSlice(posix.fd_t, cmsg.dataConst(head));
    for (fds) |fd| posix.close(fd);
    head.* = .{ .len = cmsg.length(0) };

    self.writer_end = 0;
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
