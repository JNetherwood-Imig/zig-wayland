const std = @import("std");

pub fn RingBuffer(comptime T: type) type {
    return struct {
        buffer: []T,
        start: usize,
        end: usize,

        const Self = @This();

        pub fn init(buffer: []T) Self {
            std.debug.assert(buffer.len > 0);
            return .{ .buffer = buffer, .start = 0, .end = 0 };
        }

        pub fn reset(self: *Self) void {
            self.start, self.end = .{ 0, 0 };
        }

        pub fn used(self: *const Self) usize {
            return if (self.end >= self.start)
                self.end - self.start
            else
                self.buffer.len - self.start + self.end;
        }

        pub fn available(self: *const Self) usize {
            return self.buffer.len - 1 - self.used();
        }

        pub fn put(self: *Self, item: T) bool {
            if ((self.end + 1) % self.buffer.len == self.start)
                return false;

            defer self.end = (self.end + 1) % self.buffer.len;

            self.buffer[self.end] = item;
            return true;
        }

        pub fn putMany(self: *Self, items: []const T) usize {
            const len = @min(self.available(), items.len);
            const first_len = @min(len, self.buffer.len - self.end);
            @memcpy(self.buffer[self.end..][0..first_len], items[0..first_len]);
            if (first_len != len) {
                @memcpy(self.buffer[0..self.start][0 .. len - first_len], items[first_len..len]);
            }
            self.end = (self.end + len) % self.buffer.len;
            return len;
        }

        pub fn peek(self: *const Self) ?T {
            if (self.start == self.end) return null;
            return self.buffer[self.start];
        }

        pub fn take(self: *Self) ?T {
            if (self.start == self.end) return null;
            defer self.start = (self.start + 1) % self.buffer.len;
            return self.buffer[self.start];
        }

        pub fn takeMany(self: *Self, buf: []T) usize {
            const len = @min(self.used(), buf.len);
            if (self.end == self.start) {
                return 0;
            } else if (self.end > self.start) {
                @memcpy(buf[0..len], self.buffer[self.start..self.end][0..len]);
                self.start += len;
            } else {
                const first_len = @min(len, self.end - self.start);
                @memcpy(buf[0..first_len], self.buffer[self.start..][0..first_len]);
                @memcpy(buf[first_len..len], self.buffer[0 .. len - first_len]);
                self.start = (self.start + len) % self.buffer.len;
            }
            if (self.start == self.end) self.reset();
            return len;
        }

        pub fn toIovec(self: *Self) [2]std.posix.iovec_const {
            var iov = std.mem.zeroes([2]std.posix.iovec_const);
            if (self.start <= self.end) {
                iov[0] = .{
                    .base = @ptrCast(self.buffer.ptr + self.start),
                    .len = self.used() * @sizeOf(T),
                };
            } else {
                iov[0] = .{
                    .base = @ptrCast(self.buffer.ptr + self.start),
                    .len = (self.buffer.len - self.start) * @sizeOf(T),
                };
                iov[1] = .{
                    .base = @ptrCast(self.buffer.ptr),
                    .len = self.end * @sizeOf(T),
                };
            }
            self.reset();
            return iov;
        }
    };
}

test "put/take" {
    var buf: [8]i32 = undefined; // Buffer can store 7 elems
    var rb = RingBuffer(i32).init(&buf);
    var i: i32 = 0;
    while (rb.put(i)) : (i += 1) continue;

    i = 0;
    while (rb.take()) |item| {
        try std.testing.expectEqual(i, item);
        i += 1;
    }
    try std.testing.expectEqual(@as(i32, @intCast(buf.len - 1)), i);
}

test "put many" {
    var buf: [8]i32 = undefined;
    var rb: RingBuffer(i32) = .init(&buf);
    const items = [_]i32{ 0, 1, 2, 3 };

    try std.testing.expectEqual(items.len, rb.putMany(&items));
    try std.testing.expectEqual(0, rb.take());
    try std.testing.expectEqual(items.len, rb.putMany(&items));
    try std.testing.expectEqual(0, rb.putMany(&items));

    rb.reset();

    try std.testing.expectEqual(items.len, rb.putMany(&items));
    try std.testing.expectEqual(items.len - 1, rb.putMany(&items));
}

test "take many" {
    var buf: [8]i32 = undefined;
    var rb: RingBuffer(i32) = .init(&buf);
    const items = [_]i32{ 0, 1, 2, 3, 4, 5, 6 };

    try std.testing.expectEqual(items.len, rb.putMany(&items));

    var read_buf: [4]i32 = undefined;
    try std.testing.expectEqual(read_buf.len, rb.takeMany(&read_buf));
    try std.testing.expectEqualSlices(i32, items[0..4], read_buf[0..]);
    try std.testing.expectEqual(read_buf.len - 1, rb.takeMany(&read_buf));
    try std.testing.expectEqualSlices(i32, items[4..], read_buf[0 .. read_buf.len - 1]);
}

test "take all" {
    var buf: [8]i32 = undefined;
    var rb: RingBuffer(i32) = .init(&buf);
    const items = [_]i32{ 0, 1, 2, 3 };

    try std.testing.expectEqual(items.len, rb.putMany(&items));

    var read_buf: [8]i32 = undefined;
    try std.testing.expectEqual(items.len, rb.takeMany(&read_buf));

    try std.testing.expectEqual(0, rb.start);
    try std.testing.expectEqual(0, rb.end);
}

test "to iovec" {
    var buf: [10]i32 = undefined;
    var rb: RingBuffer(i32) = .init(&buf);
    const items = [_]i32{ 0, 1, 2, 3, 4, 5, 6 };

    _ = rb.putMany(&items);
    try std.testing.expectEqual(0, rb.take());
    try std.testing.expectEqual(1, rb.take());
    try std.testing.expectEqual(2, rb.take());
    _ = rb.putMany(&items);

    const iovs = rb.toIovec();
    try std.testing.expectEqual(7 * @sizeOf(i32), iovs[0].len);
    try std.testing.expectEqual(2 * @sizeOf(i32), iovs[1].len);
}
