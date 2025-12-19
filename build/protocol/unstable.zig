//! Last updated to wayland-protocols version 1.45
//! 18 December 2025

pub const fullscreen_shell_unstable_v1 = .{
    .subpath = "unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const idle_inhibit_unstable_v1 = .{
    .subpath = "unstable/idle-inhibit/idle-inhibit-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const input_method_unstable_v1 = .{
    .subpath = "unstable/input-method/input-method-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const input_timestamps_unstable_v1 = .{
    .subpath = "unstable/input-timestamps/input-timestamps-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const keyboard_shortcuts_inhibit_unstable_v1 = .{
    .subpath = "unstable/keyboard-shortcuts-inhibit/keyboard-shortcuts-inhibit-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const pointer_constraints_unstable_v1 = .{
    .subpath = "unstable/pointer-constraints/pointer-constraints-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const pointer_gestures_unstable_v1 = .{
    .subpath = "unstable/pointer-gestures/pointer-gestures-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const primary_selection_unstable_v1 = .{
    .subpath = "unstable/primary-selection/primary-selection-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const relative_pointer_unstable_v1 = .{
    .subpath = "unstable/relative-pointer/relative-pointer-unstable-v1.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const text_input_unstable_v3 = .{
    .subpath = "unstable/text-input/text-input-unstable-v3.xml",
    .strip_prefix = "zwp",
    .imports = &.{"wayland"},
};

pub const xdg_decoration_unstable_v1 = .{
    .subpath = "unstable/xdg-decoration/xdg-decoration-unstable-v1.xml",
    .strip_prefix = "zxdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_foreign_unstable_v2 = .{
    .subpath = "unstable/xdg-foreign/xdg-foreign-unstable-v2.xml",
    .strip_prefix = "zxdg",
    .imports = &.{"wayland"},
};

pub const xdg_output_unstable_v1 = .{
    .subpath = "unstable/xdg-output/xdg-output-unstable-v1.xml",
    .strip_prefix = "zxdg",
    .imports = &.{"wayland"},
};

pub const xwayland_keyboard_grab_unstable_v1 = .{
    .subpath = "unstable/xwayland-keyboard-grab/xwayland-keyboard-grab-unstable-v1.xml",
    .strip_prefix = "zwp_xwayland",
    .imports = &.{"wayland"},
};
