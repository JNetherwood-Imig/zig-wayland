//! Components for interacting with the Wayland protocol.

pub const wire = @import("wire.zig");
pub const Connection = @import("Connection.zig");
pub const Server = @import("Server.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const SocketInfo = @import("socket_info.zig").SocketInfo;
pub const MessageUnion = @import("message_union.zig").MessageUnion;
pub const MessageHandler = @import("message_handler.zig").MessageHandler;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
