const std = @import("std");
const posix = std.posix;
const testing = std.testing;
const talloc = testing.allocator;

pub fn MsgUnion(comptime count: usize) type {
    return extern union {
        header: Header,
        buffer: [space(count)]u8,

        pub fn init() @This() {
            var self = std.mem.zeroes(@This());
            self.header = .{ .cmsg_len = length(count) };
            return self;
        }
    };
}

pub const Header = extern struct {
    cmsg_len: usize,
    cmsg_level: c_int = posix.SOL.SOCKET,
    cmsg_type: c_int = 0x01, // SCM_RIGHTS

};

pub inline fn @"align"(size: usize) usize {
    return size + @sizeOf(usize) - 1 & ~(@sizeOf(usize) - @as(usize, 1));
}

pub inline fn padding(size: usize) usize {
    return (@sizeOf(usize) - (size & (@sizeOf(usize) - 1))) & (@sizeOf(usize) - 1);
}

pub inline fn length(count: usize) usize {
    return @"align"(@sizeOf(Header)) + count * @sizeOf(posix.fd_t);
}

pub inline fn space(count: usize) usize {
    return @"align"(@sizeOf(Header)) + @"align"(count * @sizeOf(posix.fd_t));
}

pub inline fn data(cmsg: *Header) []u8 {
    const many_ptr = @as([*]Header, @ptrCast(cmsg));
    const data_ptr = @as([*]u8, @ptrCast(many_ptr + 1));
    const len = cmsg.cmsg_len - length(0);
    return data_ptr[0..len];
}

pub inline fn dataConst(cmsg: *const Header) []const u8 {
    const many_ptr = @as([*]const Header, @ptrCast(cmsg));
    const data_ptr = @as([*]const u8, @ptrCast(many_ptr + 1));
    const len = cmsg.cmsg_len - length(0);
    return data_ptr[0..len];
}

pub inline fn firstHeader(message: *const posix.msghdr) ?*const Header {
    return if (message.controllen >= @sizeOf(Header) and message.control != null)
        @as(*const Header, @ptrCast(@alignCast(message.control.?)))
    else
        null;
}

pub inline fn nextHeader(message: *const posix.msghdr, cmsg: *const Header) ?*const Header {
    if (message.control == null or cmsg.cmsg_len < @sizeOf(Header)) return null;

    const control_ptr = @as(usize, @intFromPtr(message.control.?));
    const cmsg_ptr = @as(usize, @intFromPtr(cmsg));
    const size_needed = @sizeOf(Header) + padding(cmsg.cmsg_len);

    if (control_ptr + message.controllen - cmsg_ptr < size_needed or
        control_ptr + message.controllen - cmsg_ptr - size_needed < cmsg.cmsg_len)
        return null;

    return @as(*const Header, @ptrFromInt(cmsg_ptr + @"align"(cmsg.cmsg_len)));
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
    const cmsg = Header{ .cmsg_len = buf.len };
    const cmsg_ptr = @as(*const Header, @ptrCast(@alignCast(&buf)));
    @memcpy(buf[0..@sizeOf(Header)], std.mem.asBytes(&cmsg));
    @memcpy(buf[length(0) .. length(0) + 6], "Hello!");

    try testing.expectEqual(data(cmsg_ptr)[0], 'H');
    try testing.expectEqual(data(cmsg_ptr)[8], 0);
}

test "cmsg first header" {
    var buf align(@alignOf(Header)) = [_]u8{0} ** 64;
    var cmsg = std.mem.bytesAsValue(Header, &buf);
    cmsg.cmsg_len = buf.len;
    var msg = posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &.{},
        .iovlen = 0,
        .control = cmsg,
        .controllen = cmsg.cmsg_len,
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
        cmsg.cmsg_len = len;
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
