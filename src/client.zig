pub const DynamicIdAllocator = @import("client/DynamicIdAllocator.zig");
pub const EventHandler = @import("client/EventHandler.zig");
pub const FixedBufferIdAllocator = @import("client/FixedBufferIdAllocator.zig");
pub const protocol = @import("protocol");
pub const Connection = core.Connection;
pub const Fixed = core.Fixed;
pub const IdAllocator = core.IdAllocator;

pub fn getConnectInfo() Connection.ConnectInfo {
    return Connection.ConnectInfo.default();
}

const core = @import("core");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
