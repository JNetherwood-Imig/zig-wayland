//! Last updated to wayland-protocols version 1.47
//! 30 March 2026

pub const xx_cutouts_v1 = .{
    .subpath = "experimental/xx-cutouts/xx-cutouts-v1.xml",
    .strip_prefix = "",
    .imports = &.{"wayland"},
};

pub const xx_keyboard_filter_v1 = .{
    .subpath = "experimental/xx-cutouts/xx-cutouts-v1.xml",
    .strip_prefix = "",
    .imports = &.{"wayland"},
};

pub const xx_zones_v1 = .{
    .subpath = "experimental/xx-zones/xx-zones-v1.xml",
    .strip_prefix = "",
    .imports = &.{ "wayland", "xdg_shell" },
};
