const std = @import("std");

const RingBuffer = @This();

buffer: []u8,
start: usize,
end: usize,

pub fn init(buffer: []u8) RingBuffer {
    std.debug.assert(buffer.len > 0);
    return .{ .buffer = buffer, .start = 0, .end = 0 };
}

pub fn used(self: *const RingBuffer) usize {
    return if (self.end >= self.start)
        self.end - self.start
    else
        self.buffer.len - self.start + self.end;
}

pub fn available(self: *const RingBuffer) usize {
    return self.buffer.len - self.used();
}

pub fn put(self: *RingBuffer, data: []const u8) usize {
    var written: usize = 0;
    if (self.start <= self.end) {
        const first = self.buffer[self.end..];
        const second = self.buffer[0..self.start];
    }
    return written;
}

pub fn take(self: *RingBuffer, buf: []u8) usize {}
