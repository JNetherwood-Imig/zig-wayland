const Buffer = @This();

buffer: []u8,
start: usize = 0,
end: usize = 0,

pub fn reset(self: *Buffer) void {
    self.start, self.end = .{ 0, 0 };
}

pub fn bytesAvailable(self: *const Buffer) usize {
    return self.end - self.start;
}

pub fn spaceAvailable(self: *const Buffer) usize {
    return self.buffer.len - self.end;
}

pub fn read(self: *Buffer, len: usize) ?[]const u8 {
    if (len > self.bytesAvailable()) return null;
    defer self.start += len;
    return self.buffer[self.start..self.end];
}

pub fn write(self: *Buffer, data: []const u8) usize {
    const written = @min(data.len, self.buffer.len - self.end);
    @memcpy(self.buffer[self.end .. self.end + written], data[0..written]);
    self.end += written;
    return written;
}

pub fn flush(self: *Buffer) []const u8 {
    defer self.reset();
    return self.read(self.bytesAvailable());
}
