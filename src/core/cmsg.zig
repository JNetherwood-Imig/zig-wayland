//! Private utility module for working with socket control messages.

const std = @import("std");
const posix = std.posix;
const testing = std.testing;

const alignment: usize = @sizeOf(usize);

pub const Header = extern struct {
    len: usize,
    level: c_int = posix.SOL.SOCKET,
    type: c_int = 0x01, // SCM_RIGHTS (used for passing fds)

};

/// Returns `size` rounded up to `@sizeOf(usize)` bytes.
pub inline fn @"align"(size: usize) usize {
    return size + alignment - 1 & ~(alignment - 1);
}

/// Returns the number of padding bytes added for alignment purposes.
pub inline fn padding(size: usize) usize {
    return (alignment - (size & (alignment - 1))) & (alignment - 1);
}

/// Returns the length of the cmsg buffer which stores `count` fds.
pub inline fn length(count: usize) usize {
    return @"align"(@sizeOf(Header)) + count * @sizeOf(posix.fd_t);
}

/// Returns the amount of space that should be given to a buffer which stores `count` fds.
pub inline fn space(count: usize) usize {
    return @"align"(@sizeOf(Header)) + @"align"(count * @sizeOf(posix.fd_t));
}

/// Returns a mutable slice of the cmsg data, with its length derived from the header.
pub inline fn data(cmsg: *Header) []u8 {
    const many_ptr = @as([*]Header, @ptrCast(cmsg));
    const data_ptr = @as([*]u8, @ptrCast(many_ptr + 1));
    const len = cmsg.len - length(0);
    return data_ptr[0..len];
}

/// Returns an immutable slice of the cmsg data, with its length derived from the header.
pub inline fn dataConst(cmsg: *const Header) []const u8 {
    const many_ptr = @as([*]const Header, @ptrCast(cmsg));
    const data_ptr = @as([*]const u8, @ptrCast(many_ptr + 1));
    const len = cmsg.len - length(0);
    return data_ptr[0..len];
}

/// Returns a pointer to the first control header associated with `message`,
/// or `null` if there are none.
pub inline fn firstHeader(message: *const posix.msghdr) ?*const Header {
    return if (message.controllen >= @sizeOf(Header) and message.control != null)
        @as(*const Header, @ptrCast(@alignCast(message.control.?)))
    else
        null;
}

/// Returns a pointer to the next control header after `cmsg` associated with `message`,
/// or `null` of `cmsg` is the last header.
/// Based on glibc __cmsg_nxthdr (see https://github.com/bminor/glibc/blob/master/sysdeps/unix/sysv/linux/cmsg_nxthdr.c)
pub inline fn nextHeader(message: *const posix.msghdr, cmsg: *const Header) ?*const Header {
    const control_ptr: [*]align(alignment) const u8 = @ptrCast(@alignCast(message.control.?));
    const cmsg_ptr: [*]align(alignment) const u8 = @ptrCast(cmsg);
    const size_needed = @sizeOf(Header) + padding(cmsg.len);

    if (control_ptr + message.controllen - cmsg_ptr < size_needed or
        control_ptr + message.controllen - cmsg_ptr - size_needed < cmsg.len)
        return null;

    return @as(*const Header, @ptrCast(@alignCast(cmsg_ptr + @"align"(cmsg.len))));
}

test "cmsg align" {
    try testing.expectEqual(@"align"(15), 16);
    try testing.expectEqual(@"align"(17), 24);
}

test "cmsg len" {
    try testing.expectEqual(length(1), 24);
    try testing.expectEqual(length(5), 40);
}

test "cmsg space" {
    try testing.expectEqual(length(1), 24);
    try testing.expectEqual(length(5), 40);
}

test "cmsg data" {
    var buf align(@alignOf(Header)) = [_]u8{0} ** 64;
    const cmsg = Header{ .len = buf.len };
    const cmsg_ptr = @as(*const Header, @ptrCast(@alignCast(&buf)));
    @memcpy(buf[0..@sizeOf(Header)], std.mem.asBytes(&cmsg));
    @memcpy(buf[length(0) .. length(0) + 6], "Hello!");

    try testing.expectEqual(data(cmsg_ptr)[0], 'H');
    try testing.expectEqual(data(cmsg_ptr)[8], 0);
}

test "cmsg first header" {
    var buf align(@alignOf(Header)) = [_]u8{0} ** 64;
    var cmsg = std.mem.bytesAsValue(Header, &buf);
    cmsg.len = buf.len;
    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &.{},
        .iovlen = 0,
        .control = cmsg,
        .controllen = cmsg.len,
        .flags = 0,
    };

    try testing.expectEqual(firstHeader(&msg), cmsg);
}

test "cmsg next header" {
    var buf align(@alignOf(Header)) = [_]u8{0} ** 256;
    var ptr: [*]align(8) u8 = &buf;
    for (0..8) |i| {
        const len = space(@sizeOf(i32));
        var cmsg = std.mem.bytesAsValue(Header, ptr);
        cmsg.len = len;
        std.mem.bytesAsValue(i32, data(cmsg)).* = @as(i32, @intCast(i));
        ptr += len;
    }
    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &.{},
        .iovlen = 0,
        .control = &buf,
        .controllen = space(@sizeOf(i32)) * 8,
        .flags = 0,
    };

    var head = firstHeader(&msg).?;
    try testing.expectEqual(0, data(head)[0]);
    for (1..8) |i| {
        head = nextHeader(&msg, @constCast(head)).?;
        try testing.expectEqual(i, data(head)[0]);
    }
}
