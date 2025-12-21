const std = @import("std");
const cmsg = @import("cmsg.zig");
const wire = @import("../wire.zig");

const Writer = @This();

/// The `handle` of a `Connection`
socket: std.posix.fd_t,

/// Backing buffer into which wire data is serialized.
/// Aligned to 4 bytes because the Wayland wire is encoded as 32 bit words.
buf: []align(4) u8,
/// Marks used space in wire data buffer.
end: usize,

/// The buffer into which control data is encoded.
/// Must be at least able to store a `cmsg.Header` and one or more fds.
/// Must be aligned correctly for use with `std.posix.sendmsg`
control: []align(8) u8,

/// Initialize a `Writer` targeting `socket` backed by `buf` and `fd_buf`.
/// Returns a new `Writer` equivalent to having initialized the parameters manually,
/// except for asserting that the buffer sizes are nonzero.
pub fn init(
    socket: std.posix.fd_t,
    buf: []align(4) u8,
    control: []align(8) u8,
) Writer {
    std.debug.assert(buf.len > 0 and control.len >= cmsg.space(1));
    var self = Writer{
        .socket = socket,
        .buf = buf,
        .end = 0,
        .control = control,
    };
    // Start by resetting the buffer, initializes `control` with a valid
    // `cmsg.Header` as well as zeroing the end pos.
    self.reset();
    return self;
}

pub const PutBytesError = FlushError || error{MessageTooLong};

/// Write all of `bytes` to the underlying buffer, flushing as many times as is necessary
/// to ensure that all bytes are sent.
///
/// See `flush` for error information.
pub fn putBytes(self: *Writer, bytes: []const u8) PutBytesError!void {
    if (bytes.len > wire.libwayland_max_message_size) return error.MessageTooLong;

    var written: usize = 0;
    while (written < bytes.len) {
        if (self.end == self.buf.len) try self.flush();
        const len = @min(bytes.len, self.buf.len - self.end);
        @memcpy(self.buf[self.end..][0..len], bytes[written..][0..len]);
        self.end += len;
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
        if (control_len == self.control.len) try self.flush();
        const len = @min(fds.len, (self.control.len - control_len) / @sizeOf(std.posix.fd_t));
        @memcpy(
            std.mem.bytesAsSlice(std.posix.fd_t, self.control[control_len..])[0..len],
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
    const head = self.controlHeader();
    const control = if (head.len > cmsg.length(0)) self.control.ptr else null;
    const controllen = if (head.len > cmsg.length(0)) head.len else 0;

    const msg = std.posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = control,
        .controllen = controllen,
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
    return std.mem.bytesAsValue(cmsg.Header, self.control[0..@sizeOf(cmsg.Header)]);
}

test "init" {
    var buf: [wire.libwayland_max_message_size]u8 align(4) = undefined;
    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 align(8) = undefined;
    var w: Writer = .init(-1, &buf, &control);

    try std.testing.expectEqual(0, w.end);
    try std.testing.expectEqual(std.posix.SOL.SOCKET, w.controlHeader().level);
    try std.testing.expectEqual(0x01, w.controlHeader().type);
    try std.testing.expectEqual(cmsg.length(0), w.controlHeader().len);
}

test "putBytes" {
    var buf: [wire.libwayland_max_message_size]u8 align(4) = undefined;
    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 align(8) = undefined;
    var w: Writer = .init(-1, &buf, &control);

    const bytes = "hello, world!";
    try w.putBytes(bytes);
    try std.testing.expectEqual(bytes.len, w.end);

    try w.putBytes(&.{ 0, 1, 2, 3 });
    try w.putBytes(&.{ 4, 5, 6, 7 });
    try std.testing.expectEqual(bytes.len + 8, w.end);

    const expected = bytes ++ [_]u8{ 0, 1, 2, 3 } ++ [_]u8{ 4, 5, 6, 7 };
    try std.testing.expectEqualSlices(u8, expected, w.buf[0..w.end]);

    w.reset();

    try w.putBytes(&.{ 0, 1, 2, 3 });
    try w.putBytes(&.{ 4, 5, 6, 7 });
    try std.testing.expectEqual(8, w.end);

    const expected2 = [_]u8{ 0, 1, 2, 3 } ++ [_]u8{ 4, 5, 6, 7 };
    try std.testing.expectEqualSlices(u8, &expected2, w.buf[0..w.end]);
}

test "putFds" {
    var buf: [wire.libwayland_max_message_size]u8 align(4) = undefined;
    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 align(8) = undefined;
    var w: Writer = .init(-1, &buf, &control);

    try w.putFds(&.{ -1, -2, -3 });
    try std.testing.expectEqual(cmsg.length(3), w.controlHeader().len);
}
