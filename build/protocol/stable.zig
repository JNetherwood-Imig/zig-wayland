//! Last updated to wayland-protocols version 1.47
//! 30 March 2026

pub const linux_dmabuf_v1 = .{
    .subpath = "stable/linux-dmabuf/linux-dmabuf-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const presentation_time = .{
    .subpath = "stable/presentation-time/presentation-time.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const tablet_v2 = .{
    .subpath = "stable/tablet/tablet-v2.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const viewporter = .{
    .subpath = "stable/viewporter/viewporter.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const xdg_shell = .{
    .subpath = "stable/xdg-shell/xdg-shell.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};
