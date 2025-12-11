//! Client/Server agnostic socket abstraction for exchanging messages.

const std = @import("std");
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
pub fn close(self: *Connection) void {
    posix.close(self.handle);
}

pub const FlushError = Writer.FlushError;

/// Send all outgoing data and file descriptors.
pub fn flush(self: *Connection) FlushError!void {
    return self.writer.flush();
}

/// Write data to the underlying ring buffer, flushing the connection if the ring buffer fills up.
pub fn sendMessage(self: *Connection, buffer: []const u8) FlushError!void {
    try self.writer.writeData(buffer);
}

/// Write data and file descriptors to their respective ring buffers,
/// flushing both if either fills up.
pub fn sendMessageWithFds(
    self: *Connection,
    buffer: []const u8,
    fds: []const posix.fd_t,
) Writer.FlushError!void {
    try self.writer.writeFds(fds);
    try self.writer.writeData(buffer);
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
    const libwayland_max_message_size = 4096;
    const libwayland_max_fds = 20;

    data_in: [libwayland_max_message_size]u8 = @splat(0),
    data_out: [libwayland_max_message_size]u8 = @splat(0),
    fds_in: [libwayland_max_fds]posix.fd_t = @splat(-1),
    fds_out: [libwayland_max_fds]posix.fd_t = @splat(-1),
};
