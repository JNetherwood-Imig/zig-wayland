//! Last updated to wayland-protocols version 1.47
//! 30 March 2026

pub const alpha_modifier_v1 = .{
    .subpath = "staging/alpha-modifier/alpha-modifier-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const color_management_v1 = .{
    .subpath = "staging/color-management/color-management-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const color_representation_v1 = .{
    .subpath = "staging/color-representation/color-representation-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const commit_timing_v1 = .{
    .subpath = "staging/commit-timing/commit-timing-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const content_type_v1 = .{
    .subpath = "staging/content-type/content-type-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const cursor_shape_v1 = .{
    .subpath = "staging/cursor-shape/cursor-shape-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{ "wayland", "tablet_v2" },
};

pub const drm_lease_v1 = .{
    .subpath = "staging/drm-lease/drm-lease-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const ext_background_effect_v1 = .{
    .subpath = "staging/ext-background-effect/ext-background-effect-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_data_control_v1 = .{
    .subpath = "staging/ext-data-control/ext-data-control-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_foreign_toplevel_list_v1 = .{
    .subpath = "staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_idle_notify_v1 = .{
    .subpath = "staging/ext-idle-notify/ext-idle-notify-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_image_capture_source_v1 = .{
    .subpath = "staging/ext-image-capture-source/ext-image-capture-source-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{ "wayland", "ext_foreign_toplevel_list_v1" },
};

pub const ext_image_copy_capture_v1 = .{
    .subpath = "staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{ "wayland", "ext_image_capture_source_v1" },
};

pub const ext_session_lock_v1 = .{
    .subpath = "staging/ext-session-lock/ext-session-lock-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_transient_seat_v1 = .{
    .subpath = "staging/ext-transient-seat/ext-transient-seat-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const ext_workspace_v1 = .{
    .subpath = "staging/ext-workspace/ext-workspace-v1.xml",
    .strip_prefix = "ext",
    .imports = &.{"wayland"},
};

pub const fifo_v1 = .{
    .subpath = "staging/fifo/fifo-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const fractional_scale_v1 = .{
    .subpath = "staging/fractional-scale/fractional-scale-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const linux_drm_syncobj_v1 = .{
    .subpath = "staging/linux-drm-syncobj/linux-drm-syncobj-v1.xml",
    .strip_prefix = "wp_linux",
    .imports = &.{"wayland"},
};

pub const pointer_warp_v1 = .{
    .subpath = "staging/pointer-warp/pointer-warp-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const security_context_v1 = .{
    .subpath = "staging/security-context/security-context-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const single_pixel_buffer_v1 = .{
    .subpath = "staging/single-pixel-buffer/single-pixel-buffer-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const tearing_control_v1 = .{
    .subpath = "staging/tearing-control/tearing-control-v1.xml",
    .strip_prefix = "wp",
    .imports = &.{"wayland"},
};

pub const xdg_activation_v1 = .{
    .subpath = "staging/xdg-activation/xdg-activation-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};

pub const xdg_dialog_v1 = .{
    .subpath = "staging/xdg-dialog/xdg-dialog-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_session_management_v1 = .{
    .subpath = "staging/xdg-session-management/xdg-session-management-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_system_bell_v1 = .{
    .subpath = "staging/xdg-system-bell/xdg-system-bell-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{"wayland"},
};

pub const xdg_toplevel_drag_v1 = .{
    .subpath = "staging/xdg-toplevel-drag/xdg-toplevel-drag-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_toplevel_icon_v1 = .{
    .subpath = "staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xdg_toplevel_tag_v1 = .{
    .subpath = "staging/xdg-toplevel-tag/xdg-toplevel-tag-v1.xml",
    .strip_prefix = "xdg",
    .imports = &.{ "wayland", "xdg_shell" },
};

pub const xwayland_shell_v1 = .{
    .subpath = "staging/xwayland-shell/xwayland-shell-v1.xml",
    .strip_prefix = "xwayland",
    .imports = &.{"wayland"},
};
