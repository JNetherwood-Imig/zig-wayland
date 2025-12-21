//! Client/Server agnostic socket abstraction for exchanging messages.

const std = @import("std");
const wire = @import("wire.zig");
const cmsg = @import("Connection/cmsg.zig");
const IdAllocator = @import("IdAllocator.zig");
const Reader = @import("Connection/Reader.zig");
const Writer = @import("Connection/Writer.zig");
const posix = std.posix;

const Connection = @This();

handle: posix.fd_t,
ida: IdAllocator,
/// Ring buffer wrapper for outgoing data and file descriptors
writer: Writer,
/// Ring buffer wrapper for incoming data and file descriptors
reader: Reader,

/// Initializes all fields of a `Connection`,
/// assuming that `handle` is already an established socket.
pub fn init(handle: posix.fd_t, ida: IdAllocator, buffers: *Buffers) Connection {
    return .{
        .handle = handle,
        .ida = ida,
        .reader = .init(handle, &buffers.data_in, &buffers.fds_in),
        .writer = .init(handle, &buffers.data_out, &buffers.fds_out),
    };
}

/// Close the underlying connection file descriptor.
pub fn deinit(self: *Connection) void {
    posix.close(self.handle);
    self.* = undefined;
}

pub const FlushError = Writer.FlushError;

/// Sends all outgoing messages over the wire, passing buffered file descriptors over
/// ancillary data using SCM_RIGHTS.
pub fn flush(self: *Connection) FlushError!void {
    return self.writer.flush();
}

pub const SendMessageError = Writer.PutBytesError;

/// Write a message to the connection buffer, flushing only if there is insufficient space.
///
/// `buffer.len` **must** be less than or equal to `wire.libwayland_max_message_length` (4096), and
pub fn sendMessage(self: *Connection, buffer: []const u8) Writer.PutBytesError!void {
    try self.writer.putBytes(buffer);
}

pub const SendMessageWithFdsError = Writer.PutBytesError || Writer.PutFdsError;

/// Write a message with file descriptors to their respective buffers, flushing them together in the
/// event that either would overflow.
///
/// `buffer.len` **must** be less than or equal to `wire.libwayland_max_message_length` (4096), and
/// `fds.len` **must** be less than or equal to `wire.libwayland_max_message_args` (20).
pub fn sendMessageWithFds(
    self: *Connection,
    buffer: []const u8,
    fds: []const posix.fd_t,
) SendMessageWithFdsError!void {
    try self.writer.putBytes(buffer);
    try self.writer.putFds(fds);
}

pub const PollEventsError = posix.PollError || Reader.ReadIncomingError;

/// Poll for events on the socket file descriptor and read incoming messages.
/// Stores incoming data and file descriptors in their respective ring buffers to be popped later
/// without performing another read.
/// Returns immediately if `wait` is false, otherwise it will wait indefinately.
pub fn pollEvents(self: *Connection, wait: bool) PollEventsError!bool {
    var pfd = posix.pollfd{
        .fd = self.handle,
        .events = posix.POLL.IN,
        .revents = 0,
    };
    // If we get no signaled fds before timing out, return false
    if (try posix.poll((&pfd)[0..1], if (wait) -1 else 0) == 0) return false;
    // We have data, so read it into the buffer
    try self.reader.readIncoming();
    return true;
}

/// Utility struct to ease the process of creating backing buffers to be used by the connection.
/// These are created on the stack because the reasonably can be,
/// but they can be manually created in whatever way the user pleases.
/// This struct creates buffers that hold the libwayland-imposed maximum message size worth of data
/// and the libwayland maximum closure argument count worth of file descriptors.
pub const Buffers = struct {
    data_in: [wire.libwayland_max_message_size]u8 align(4) = @splat(0),
    data_out: [wire.libwayland_max_message_size]u8 align(4) = @splat(0),
    fds_in: [wire.libwayland_max_message_args]posix.fd_t align(8) = @splat(-1),
    fds_out: [cmsg.space(wire.libwayland_max_message_args)]u8 align(8) = @splat(0),
};

test {
    _ = Writer;
}
