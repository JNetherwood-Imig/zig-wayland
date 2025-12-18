//! Description idk
//! Some copyright

/// Shell singleton
pub const WmBase = enum(u32) {
    invalid,
    _,
    pub const interface = "xdg_wm_base";
    pub const getXdgSurface = fn (_: WmBase, _: wayland.Surface) anyerror!Surface;
};
/// Desktop surface
pub const Surface = enum(u32) {
    invalid,
    _,
    pub const interface = "xdg_surface";
    pub const getToplevel = fn (_: Surface) anyerror!Toplevel;
};
/// Toplevel window
pub const Toplevel = enum(u32) {
    invalid,
    _,
    pub const interface = "xdg_toplevel";
};

const wayland = @import("wayland.zig");
