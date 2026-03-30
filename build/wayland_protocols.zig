pub const stable = .{
    .@"xdg-shell" = .{ "xdg", .{}, .{} },
};

pub const staging = .{
    .@"xdg-toplevel-tag" = .{ "xdg", &.{1}, &.{"xdg-shell"} },
};
