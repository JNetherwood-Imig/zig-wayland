//! Components for interacting with the Wayland protocol.

pub const wire = @import("wire.zig");
pub const Connection = @import("Connection.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const EventHandler = @import("event_handler.zig").EventHandler;
pub const ConnectInfo = @import("connect_info.zig").ConnectInfo;
pub const EventUnion = @import("event_union.zig").EventUnion;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
