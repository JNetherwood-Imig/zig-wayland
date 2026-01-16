//! Private utility module for working with socket control messages.

const std = @import("std");
const alignment: usize = @sizeOf(usize);

pub const Header = extern struct {
    len: usize,
    level: c_int = std.os.linux.SOL.SOCKET,
    type: c_int = 0x01, // SCM_RIGHTS (used for passing fds)

};

/// Returns `size` rounded up to `@sizeOf(usize)` bytes.
pub inline fn @"align"(size: usize) usize {
    return size + alignment - 1 & ~(alignment - 1);
}

/// Returns the length of the cmsg buffer which stores `count` fds.
pub inline fn length(count: usize) usize {
    return @"align"(@sizeOf(Header)) + count * @sizeOf(i32);
}

/// Returns the amount of space that should be given to a buffer which stores `count` fds.
pub inline fn space(count: usize) usize {
    return @"align"(@sizeOf(Header)) + @"align"(count * @sizeOf(i32));
}

test "cmsg align" {
    try std.testing.expectEqual(@"align"(15), 16);
    try std.testing.expectEqual(@"align"(17), 24);
}

test "cmsg len" {
    try std.testing.expectEqual(20, length(1));
    try std.testing.expectEqual(36, length(5));
}

test "cmsg space" {
    try std.testing.expectEqual(24, space(1));
    try std.testing.expectEqual(40, space(5));
}
