//! Components for interacting with the Wayland protocol.

// Shared components
pub const wire = @import("wire.zig");
pub const Connection = @import("Connection.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");

// Client-specific components
pub const client = struct {
    pub const EventHandler = @import("event_handler.zig").EventHandler;
    pub const ConnectInfo = @import("connect_info.zig").ConnectInfo;
};

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
