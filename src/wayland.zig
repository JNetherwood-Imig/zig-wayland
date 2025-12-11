pub const Connection = @import("Connection.zig");
pub const Fd = @import("Fd.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const ClientIdAllocator = @import("ClientIdAllocator.zig");
pub const ServerIdAllocator = @import("ServerIdAllocator.zig");

pub fn getConnectInfo() Connection.ConnectInfo {
    return Connection.ConnectInfo.default();
}

test {
    _ = Connection;
    _ = Fd;
    _ = Fixed;
    _ = IdAllocator;
    _ = ClientIdAllocator;
    _ = ServerIdAllocator;
    _ = @import("cmsg.zig");
    _ = @import("scanner.zig");
    _ = @import("wire.zig");
}
