//! Components for interacting with the Wayland protocol.

pub const wire = @import("wire.zig");
pub const Connection = @import("Connection.zig");
pub const Fixed = @import("Fixed.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const SocketInfo = @import("socket_info.zig").SocketInfo;
pub const IncomingMessageUnion = @import("incoming_message_union.zig").IncomingMessageUnion;
pub const IncomingMessageHandler = @import("incoming_message_handler.zig").IncomingMessageHandler;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
