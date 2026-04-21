const std = @import("std");
const alignment: usize = @sizeOf(usize);

/// `cmsghdr` with some default values.
pub const Header = extern struct {
    len: usize,
    level: c_int = std.posix.system.SOL.SOCKET,
    type: c_int = std.posix.system.SCM.RIGHTS,
};

/// Rounds `size` up to the nearest multiple of `@alignOf(usize)`
pub inline fn @"align"(size: usize) usize {
    return size + alignment - 1 & ~(alignment - 1);
}

/// Calculates padding that will be added to `size` by `align`.
pub inline fn padding(size: usize) usize {
    return (alignment - (size & (alignment - 1))) & (alignment - 1);
}

/// Calculates length of a message containing `count` fds.
pub inline fn length(count: usize) usize {
    return @"align"(@sizeOf(Header)) + count * @sizeOf(std.posix.fd_t);
}

/// Calculates required space for a message buffer that will contain `count` fds.
pub inline fn space(count: usize) usize {
    return @"align"(@sizeOf(Header)) + @"align"(count * @sizeOf(std.posix.fd_t));
}

/// Gets first control header from `message`, or null if no control messages were received.
pub inline fn firstHeader(message: *const std.posix.msghdr) ?*const Header {
    return if (message.controllen >= @sizeOf(Header) and message.control != null)
        @as(*const Header, @ptrCast(@alignCast(message.control.?)))
    else
        null;
}

/// Gets next control header from message, or null if no further control messages were received.
pub inline fn nextHeader(message: *const std.posix.msghdr, cmsg: *const Header) ?*const Header {
    const control_ptr: [*]align(alignment) const u8 = @ptrCast(@alignCast(message.control.?));
    const cmsg_ptr: [*]align(alignment) const u8 = @ptrCast(cmsg);
    const size_needed = @sizeOf(Header) + padding(cmsg.len);

    if (control_ptr + message.controllen - cmsg_ptr < size_needed or
        control_ptr + message.controllen - cmsg_ptr - size_needed < cmsg.len)
        return null;

    return @as(*const Header, @ptrCast(@alignCast(cmsg_ptr + @"align"(cmsg.len))));
}

/// Gets data blob from the control message.
pub inline fn data(head: *const Header) []const u8 {
    const many_ptr = @as([*]const Header, @ptrCast(head));
    const data_ptr = @as([*]const u8, @ptrCast(many_ptr + 1));
    const len = head.len - length(0);
    return data_ptr[0..len];
}
