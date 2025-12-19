//! Last updated to wlr-protocols master
//! 18 December 2025

pub const wlr_export_dmabuf_unstable_v1 = .{
    .subpath = "unstable/wlr-export-dmabuf-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_foreign_toplevel_management_unstable_v1 = .{
    .subpath = "unstable/wlr-foreign-toplevel-management-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_gamma_control_unstable_v1 = .{
    .subpath = "unstable/wlr-gamma-control-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_input_inhibitor_unstable_v1 = .{
    .subpath = "unstable/wlr-input-inhibitor-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_layer_shell_unstable_v1 = .{
    .subpath = "unstable/wlr-layer-shell-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const wlr_output_management_unstable_v1 = .{
    .subpath = "unstable/wlr-output-management-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_output_power_management_unstable_v1 = .{
    .subpath = "unstable/wlr-output-power-management-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};

pub const wlr_virtual_pointer_unstable_v1 = .{
    .subpath = "unstable/wlr-virtual-pointer-unstable-v1.xml",
    .strip_prefix = "zwlr",
    .imports = &.{"wayland"},
};
