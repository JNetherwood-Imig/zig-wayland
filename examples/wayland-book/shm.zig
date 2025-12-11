const std = @import("std");

pub fn allocateShmFile(size: usize) !std.posix.fd_t {
    const fd = try createShmFile();
    try std.posix.ftruncate(fd, size);
    return fd;
}

fn createShmFile() !std.posix.fd_t {
    while (true) {
        var path: [22:0]u8 = @splat(0);
        @memcpy(path[0..16], "/dev/shm/wl_shm-");
        try randomize(path[path.len - 6 ..]);
        const fd = std.posix.open(
            &path,
            .{
                .ACCMODE = .RDWR,
                .CREAT = true,
                .CLOEXEC = true,
                .EXCL = true,
                .NOFOLLOW = true,
            },
            0o0600,
        ) catch continue;
        try std.posix.unlink(&path);
        return fd;
    }
}

fn randomize(buf: []u8) !void {
    const ts = try std.posix.clock_gettime(.REALTIME);
    var r = ts.nsec;
    for (0..buf.len) |i| {
        buf[i] = 'A' + @as(u8, @intCast((r & 15) + (r & 16) * 2));
        r >>= 5;
    }
}
