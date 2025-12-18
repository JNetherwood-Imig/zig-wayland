//! 1.45

pub const alpha_modifier = .{
    .subpath = "alpha-modifier/alpha-modifier-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const color_management = .{
    .subpath = "color-management/color-management-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const color_representation = .{
    .subpath = "color-representation/color-representation-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const commit_timing = .{
    .subpath = "commit-timing/commit-timing-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const content_type = .{
    .subpath = "content-type/content-type-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const cursor_shape = .{
    .subpath = "cursor-shape/cursor-shape-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{ "wayland", "tablet_v2" },
};

pub const drm_lease = .{
    .subpath = "drm-lease/drm-lease-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const ext_background_effect = .{
    .subpath = "ext-background-effect/ext-background-effect-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_data_control = .{
    .subpath = "ext-data-control/ext-data-control-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_foreign_toplevel_list_v1 = .{
    .subpath = "ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_idle_notify = .{
    .subpath = "ext-idle-notify/ext-idle-notify-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_image_capture_source_v1 = .{
    .subpath = "ext-image-capture-source/ext-image-capture-source-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{ "wayland", "ext_foreign_toplevel_list_v1" },
};

pub const ext_image_copy_capture_v1 = .{
    .subpath = "ext-image-copy-capture/ext-image-copy-capture-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{ "wayland", "ext_image_capture_source_v1" },
};

pub const ext_session_lock = .{
    .subpath = "ext-session-lock/ext-session-lock-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_transient_seat = .{
    .subpath = "ext-transient-seat/ext-transient-seat-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_workspace = .{
    .subpath = "ext-workspace/ext-workspace-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const fifo = .{
    .subpath = "fifo/fifo-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const fractional_scale = .{
    .subpath = "fractional-scale/fractional-scale-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const linux_drm_syncobj = .{
    .subpath = "linux-drm-syncobj/linux-drm-syncobj-v1.xml",
    .strip_prefix = "wp_linux",
    .imports = &.{"wayland"},
};

pub const pointer_warp = .{
    .subpath = "pointer-warp/pointer-warp-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const security_context = .{
    .subpath = "security-context/security-context-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const single_pixel_buffer = .{
    .subpath = "single-pixel-buffer/single-pixel-buffer-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const tearing_control = .{
    .subpath = "tearing-control/tearing-control-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const xdg_activation = .{
    .subpath = "xdg-activation/xdg-activation-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};

pub const xdg_dialog = .{
    .subpath = "xdg-dialog/xdg-dialog-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_system_bell = .{
    .subpath = "xdg-system-bell/xdg-system-bell-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};

pub const xdg_toplevel_drag = .{
    .subpath = "xdg-toplevel-drag/xdg-toplevel-drag-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_toplevel_icon = .{
    .subpath = "xdg-toplevel-icon/xdg-toplevel-icon-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_toplevel_tag = .{
    .subpath = "xdg-toplevel-tag/xdg-toplevel-tag-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xwayland_shell = .{
    .subpath = "xwayland-shell/xwayland-shell-v1.xml",
    .strip_prefix = "xwayland",
    .imports = &.{"wayland"},
};
