//! A simple API for interacting with the Wayland protocol.
//!
//! Includes both client and server components.
//!
//! Copyright © 2025 Jackson Netherwood-Imig.

pub const wire = @import("wire.zig");
pub const Fixed = @import("fixed.zig").Fixed;
pub const Server = @import("Server.zig");
pub const Connection = @import("Connection.zig");
pub const IdAllocator = @import("IdAllocator.zig");
pub const SocketInfo = socket_info.SocketInfo;
pub const MessageUnion = message_union.MessageUnion;
pub const MessageHandler = message_handler.MessageHandler;

pub const MessageSendError = IdAllocator.AllocError ||
    Connection.PutError ||
    Connection.PutFdsError;

const socket_info = @import("socket_info.zig");
const message_union = @import("message_union.zig");
const message_handler = @import("message_handler.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
    _ = socket_info;
    _ = message_union;
    _ = message_handler;
}
