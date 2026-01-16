//! Buffered socket abstraction for exchanging messages according to the wayland wire format.
//! See `wire.zig` for serialization and deserialization information.

const std = @import("std");
const wire = @import("wire.zig");

const Connection = @This();

socket: std.Io.net.Socket,

read_buf: [wire.libwayland_max_message_size]u8 align(4) = @splat(0),
write_buf: [wire.libwayland_max_message_size]u8 align(4) = @splat(0),
fd_read_buf: [wire.libwayland_max_message_args]i32 = @splat(-1),
fd_write_buf: [wire.libwayland_max_message_args]i32 = @splat(-1),

reader_start: usize = 0,
reader_end: usize = 0,
reader_fd_start: usize = 0,
reader_fd_end: usize = 0,

writer_end: usize = 0,
writer_fd_end: usize = 0,

/// Close the underlying connection file descriptor.
pub fn deinit(self: *Connection, io: std.Io) void {
    self.socket.close(io);
    self.* = undefined;
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
pub fn peekFds(self: *const Connection, n: usize) ?[]const i32 {
    if (n > self.reader_fd_end - self.reader_fd_start) return null;
    return self.fd_read_buf[self.reader_fd_start..][0..n];
}

/// Advances the head of the fd buffer `n` fds.
pub fn discardFds(self: *Connection, n: usize) void {
    std.debug.assert(n <= self.reader_fd_end - self.reader_fd_start);
    self.reader_fd_start += n;
}

pub const ReadIncomingError = std.Io.net.Socket.ReceiveTimeoutError || error{ConnectionClosed};

/// Read and buffer incoming data and fds.
pub fn readIncoming(self: *Connection, io: std.Io, timeout: std.Io.Timeout) ReadIncomingError!void {
    // Start by shifting leftover bytes to the start of the buffer to make room for incoming data.
    self.resetReader();

    var buf: [4096]u8 = undefined;
    var control: [96]u8 align(8) = @splat(0);
    var message = std.Io.net.IncomingMessage{
        .data = &.{},
        .control = &control,
        .flags = undefined,
        .from = undefined,
    };

    const maybe_err, const count = self.socket.receiveManyTimeout(
        io,
        (&message)[0..1],
        &buf,
        .{},
        timeout,
    );

    if (maybe_err) |err| return err;
    std.debug.assert(count == 1);

    const read = message.data;
    if (read.len == 0) return error.ConnectionClosed;

    std.debug.assert(read.len < self.read_buf.len - self.reader_end);
    @memcpy(self.read_buf[self.reader_end..][0..read.len], read);
    self.reader_end += read.len;

    const fds = std.mem.bytesAsSlice(i32, message.control);
    std.debug.assert(self.reader_fd_end + fds.len < self.fd_read_buf.len);
    @memcpy(self.fd_read_buf[self.reader_fd_end..][0..fds.len], fds);
    self.reader_fd_end += 1;
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
pub fn put(self: *Connection, io: std.Io, bytes: []const u8) PutError!void {
    if (bytes.len > wire.libwayland_max_message_size)
        return error.MessageTooLong;

    var written: usize = 0;
    while (written < bytes.len) {
        if (self.writer_end == self.write_buf.len) try self.flush(io);
        const len = @min(bytes.len, self.write_buf.len - self.writer_end);
        @memcpy(self.write_buf[self.writer_end..][0..len], bytes[written..][0..len]);
        self.writer_end += len;
        written += len;
    }
}

pub const PutFdsError = FlushError || error{
    TooManyFds,
    BadFd,
    ProcessFdQuotaExceeded,
    Unexpected,
};

/// Write all of `fds` to the control buffer, incrementing the cmsg.Header data encoded at the
/// start of the buffer to match. This function will flush the buffers if there is insufficient
/// space to accomodate `fds`.
///
/// See `flush` for error information.
pub fn putFds(self: *Connection, io: std.Io, fds: []const i32) PutFdsError!void {
    if (fds.len > wire.libwayland_max_message_args)
        return error.TooManyFds;

    for (fds) |fd| {
        if (self.writer_fd_end == self.fd_write_buf.len)
            try self.flush(io);

        const dup: i32 = fd: {
            const rc = std.os.linux.dup(fd);
            switch (std.posix.errno(rc)) {
                .SUCCESS => break :fd @intCast(rc),
                .BADF => return error.BadFd,
                .MFILE => return error.ProcessFdQuotaExceeded,
                else => |err| return std.posix.unexpectedErrno(err),
            }
        };
        self.fd_write_buf[self.writer_fd_end] = dup;
        self.writer_fd_end += 1;
    }
}

pub const FlushError = std.Io.net.Socket.SendError || error{ConnectionClosed};

/// Flush the contents of both the data and fd buffers to the socket.
pub fn flush(self: *Connection, io: std.Io) FlushError!void {
    // We don't have anything to send.
    if (self.writer_end == 0) return;

    var control: [96]u8 = undefined;
    const control_len = 16 + self.writer_fd_end * 4;
    const rounded_control_len = (control_len + 7) & ~@as(usize, 7);
    std.mem.bytesAsValue(extern struct {
        len: usize,
        level: i32,
        type: i32,
    }, control[0..16]).* = .{
        .len = control_len,
        .level = 0x01,
        .type = 0x01,
    };
    @memcpy(control[16..control_len], std.mem.sliceAsBytes(self.fd_write_buf[0..self.writer_fd_end]));
    const maybe_control = if (self.writer_fd_end > 0) control[0..rounded_control_len] else &.{};

    var message = std.Io.net.OutgoingMessage{
        .address = null,
        // .address = &addr,
        .control = maybe_control,
        .data_ptr = &self.write_buf,
        .data_len = self.writer_end,
    };

    try self.socket.sendMany(io, (&message)[0..1], .{});

    if (message.data_len == 0) return error.ConnectionClosed;

    self.writer_end = 0;
    self.writer_fd_end = 0;
}
