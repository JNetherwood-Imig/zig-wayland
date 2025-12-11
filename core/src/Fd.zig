const std = @import("std");
const posix = std.posix;

const Fd = @This();

raw: posix.fd_t,

pub inline fn init(raw: posix.fd_t) !Fd {
    const self = Fd{ .raw = raw };
    try self.validate();
    return self;
}

pub inline fn initUnchecked(raw: posix.fd_t) Fd {
    return .{ .raw = raw };
}

pub inline fn fromStdFile(file: std.fs.File) Fd {
    return .initUnchecked(file.handle);
}

pub fn deinit(self: Fd) void {
    posix.close(self.raw);
}

pub fn validate(self: Fd) !void {
    return switch (posix.errno(posix.system.fcntl(self.raw, posix.F.GETFD, 0))) {
        .SUCCESS => {},
        .BADF => error.InvalidFd,
        else => unreachable,
    };
}

test "validate" {
    try Fd.fromStdFile(.stderr()).validate();
    try std.testing.expectError(error.InvalidFd, Fd.init(-1));
}
