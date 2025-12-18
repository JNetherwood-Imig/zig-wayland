//! 1.45

pub const linux_dmabuf = .{
    .subpath = "linux-dmabuf/linux-dmabuf-v1.xml",
    .strip_prefix = "zwp",
};

pub const presentation_time = .{
    .subpath = "presentation-time/presentation-time.xml",
    .strip_prefix = "wp",
};

pub const tablet = .{
    .subpath = "tablet/tablet-v2.xml",
    .strip_prefix = "zwp",
};

pub const viewporter = .{
    .subpath = "viewporter/viewporter.xml",
    .strip_prefix = "wp",
};

pub const xdg_shell = .{
    .subpath = "xdg-shell/xdg-shell.xml",
    .strip_prefix = "xdg",
};
