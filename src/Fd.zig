raw: posix.fd_t,

pub fn init(raw: posix.fd_t) ValidateError!Fd {
    const self = Fd{ .raw = raw };
    try self.validate();
    return self;
}

pub fn initUnchecked(raw: posix.fd_t) Fd {
    return .{ .raw = raw };
}

pub fn fromStdFile(file: std.fs.File) Fd {
    return .initUnchecked(file.handle);
}

pub fn close(self: Fd) void {
    posix.close(self.raw);
}

pub fn validate(self: Fd) ValidateError!void {
    return switch (posix.errno(posix.system.fcntl(self.raw, posix.F.GETFD, 0))) {
        .SUCCESS => {},
        .BADF => error.InvalidFd,
        else => unreachable,
    };
}

pub const ValidateError = error{InvalidFd};

const std = @import("std");
const posix = std.posix;

const Fd = @This();

test "validate" {
    try Fd.fromStdFile(.stderr()).validate();
    try std.testing.expectError(error.InvalidFd, Fd.init(-1));
}
