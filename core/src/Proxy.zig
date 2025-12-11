const std = @import("std");

const Proxy = @This();

pub const dummy = Proxy{ .id = 0, .version = 1 };

id: u32,
version: u32,
