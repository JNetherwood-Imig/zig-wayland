//! Last updated to wayland-protocols version 1.45
//! 18 December 2025

pub const linux_dmabuf_v1 = .{
    .subpath = "linux-dmabuf/linux-dmabuf-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const presentation_time = .{
    .subpath = "presentation-time/presentation-time.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const tablet_v2 = .{
    .subpath = "tablet/tablet-v2.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const viewporter = .{
    .subpath = "viewporter/viewporter.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const xdg_shell = .{
    .subpath = "xdg-shell/xdg-shell.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};
