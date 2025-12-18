//! Some custom protocol
//! Copyright me

/// Do something
pub const Interface = enum(u32) {
    invalid,
    _,
    pub const interface = "custom_interface";
    pub const request = fn (_: Interface, _: wayland.Surface, _: xdg_shell.Surface) anyerror!void{};
};

const wayland = @import("root/wayland.zig");
pub const xdg_shell = @import("root/xdg_shell.zig");
