//! Core components of Wayland client API

const core = @import("core");

pub const DynamicIdAllocator = @import("client/DynamicIdAllocator.zig");
pub const FixedBufferIdAllocator = @import("client/FixedBufferIdAllocator.zig");
pub const ConnectInfo = @import("client/connect_info.zig").ConnectInfo;
pub const EventHandler = @import("client/event_handler.zig").EventHandler;
pub const Fixed = core.Fixed;
pub const Connection = core.Connection;
pub const IdAllocator = core.IdAllocator;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
