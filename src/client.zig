//! Core components of Wayland client API

const core = @import("core");

pub const DynamicIdAllocator = @import("client/DynamicIdAllocator.zig");
pub const FixedBufferIdAllocator = @import("client/FixedBufferIdAllocator.zig");
pub const EventHandler = @import("client/event_handler.zig").EventHandler;
pub const Fixed = core.Fixed;
pub const Connection = core.Connection;
pub const IdAllocator = core.IdAllocator;

pub fn getConnectInfo() Connection.ConnectInfo {
    return Connection.ConnectInfo.default();
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
