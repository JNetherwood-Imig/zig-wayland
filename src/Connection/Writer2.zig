const std = @import("std");
const cmsg = @import("cmsg.zig");
const wire = @import("../wire.zig");

const Writer = @This();

/// The `handle` of a `Connection`
socket: std.posix.fd_t,

/// Backing buffer into which wire data is serialized.
buf: []u8,
/// Marks used space in wire data buffer.
end: usize,

/// The buffer into which control data is encoded.
/// Must be at least able to store a `cmsg.Header` and one or more fds.
control_buf: []u8,

/// Initialize a `Writer` targeting `socket` backed by `buf` and `fd_buf`.
/// Returns a new `Writer` equivalent to having initialized the parameters manually,
/// except for asserting that the buffer sizes are nonzero.
pub fn init(socket: std.posix.fd_t, buf: []u8, control_buf: []u8) Writer {
    std.debug.assert(buf.len > 0 and control_buf.len >= cmsg.space(1));
    var self = Writer{
        .socket = socket,
        .buf = buf,
        .end = 0,
        .control_buf = control_buf,
    };
    // Start by resetting the buffer, which actually initializes control_buf with a valid header
    // as well as zeroing the end pos.
    self.reset();
    return self;
}

pub const PutBytesError = FlushError || error{MessageTooLong};

/// Write all of `bytes` to the underlying buffer, flushing as many times as is necessary
/// to ensure that all bytes are sent.
///
/// See `flush` for error information.
pub fn putBytes(self: *Writer, bytes: []const u8) PutBytesError!void {
    if (bytes.len > wire.libwayland_max_message_length) return error.MessageTooLong;

    var written: usize = 0;
    while (written < bytes.len) {
        if (self.end == self.buf.len) try self.flush();
        const len = @min(bytes.len, self.buf.len - self.end);
        @memcpy(self.buf[self.end..][0..len], bytes[written..][0..len]);
        self.len += len;
        written += len;
    }
}

pub const PutFdsError = FlushError || error{TooManyFds};

/// Write all of `fds` to the control buffer, incrementing the cmsg.Header data encoded at the
/// start of the buffer to match. This function will flush the buffers if there is insufficient
/// space to accomodate `fds`.
///
/// See `flush` for error information.
pub fn putFds(self: *Writer, fds: []const std.posix.fd_t) PutFdsError!void {
    if (fds.len > wire.libwayland_max_message_args) return error.TooManyFds;

    var count: usize = 0;
    while (count < fds.len) {
        const control_len = self.controlHeader().len;
        if (control_len == self.control_buf.len) try self.flush();
        const len = @min(fds.len, (self.control_buf.len - control_len) / @sizeOf(std.posix.fd_t));
        @memcpy(
            std.mem.bytesAsSlice(std.posix.fd_t, self.control_buf[control_len..])[0..len],
            fds[count..][0..len],
        );
        self.controlHeader().len += len * @sizeOf(std.posix.fd_t);
        count += len;
    }
}

pub const FlushError = std.posix.SendMsgError || error{ConnectionClosed};

/// Flush the contents of both the data and fd buffers to the socket.
/// This function blocks if `std.posix.sendmsg` blocks, but this is very unlikely.
///
/// Returns `void` on success.
/// Returns `error.ConnectionClosed` if the send completes, but no bytes were sent,
/// indicating that the other end of the connection has closed.
/// Returns some member of `std.posix.SendMsgError` if the call to sendmsg fails.
pub fn flush(self: *Writer) FlushError!void {
    // We don't have anything to send.
    if (self.end == 0) return;

    const iov = [1]std.posix.iovec_const{.{ .base = self.buf.ptr, .len = self.end }};

    const msg = std.posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .control = self.control_buf,
        .controllen = self.control_buf.len,
        .flags = 0,
    };

    // This is blocking, maybe it shouldn't be?
    const sent = try std.posix.sendmsg(self.socket, &msg, 0);

    // The sendmsg returned successfully, but wrote nothing because the other end of the
    // connection was closed, so we should return an error to avoid another function busy-looping
    // because it expects either successful completion of the send or otherwise an error.
    if (sent == 0) return error.ConnectionClosed;

    // Reset data buffer end pos and control header len.
    self.reset();
}

fn reset(self: *Writer) void {
    self.end = 0;
    self.controlHeader().* = .{ .len = cmsg.length(0) };
}

fn controlHeader(self: *Writer) *cmsg.Header {
    return std.mem.bytesAsValue(cmsg.Header, self.control_buf[0..@sizeOf(cmsg.Header)]);
}
