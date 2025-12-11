pub const DynamicIdAllocator = @import("client/DynamicIdAllocator.zig");
pub const FixedBufferIdAllocator = @import("client/FixedBufferIdAllocator.zig");
pub const IdAllocator = core.IdAllocator;

pub const EventHandler = event_handler.EventHandler;

pub const Connection = core.Connection;

pub const Fixed = core.Fixed;

pub const protocol = @import("client_protocol");

pub fn getConnectInfo() Connection.ConnectInfo {
    return Connection.ConnectInfo.default();
}

const core = @import("core");
const event_handler = @import("client/event_handler.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
