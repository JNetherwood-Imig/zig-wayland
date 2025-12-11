pub const wire = @import("wire.zig");
pub const Connection = @import("Connection.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const ClientIdAllocator = @import("ClientIdAllocator.zig");
pub const ServerIdAllocator = @import("ServerIdAllocator.zig");
pub const FixedBufferClientIdAllocator = @import("FixedBufferClientIdAllocator.zig");
pub const FixedBufferServerIdAllocator = @import("FixedBufferServerIdAllocator.zig");
pub const client_protocol = @import("client_protocol");

pub fn getConnectInfo() Connection.ConnectInfo {
    return Connection.ConnectInfo.default();
}

test {
    _ = Connection;
    _ = Fixed;
    _ = IdAllocator;
    _ = ClientIdAllocator;
    _ = ServerIdAllocator;
    _ = FixedBufferClientIdAllocator;
    _ = FixedBufferServerIdAllocator;
    _ = @import("cmsg.zig");
}
