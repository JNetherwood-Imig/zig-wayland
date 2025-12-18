//! Core protocol
//! Copyright whatever

/// Display singleton
pub const Display = enum(u32) {
    invalid,
    _,
    pub const interface = "wl_display";
};
/// Registry singleton
pub const Registry = enum(u32) {
    invalid,
    _,
    pub const interface = "wl_registry";
};
/// Compositor singleton
pub const Compositor = enum(u32) {
    invalid,
    _,
    pub const interface = "wl_compositor";
};
/// Surface object
pub const Surface = enum(u32) {
    invalid,
    _,
    pub const interface = "wl_surface";
};
