//! A simple API for interacting with the Wayland protocol.
//!
//! Includes both client and server components.
//!
//! Copyright © 2025 Jackson Netherwood-Imig.

pub const Address = @import("Addresss.zig");
pub const Connection = @import("Connection.zig");
pub const Fixed = @import("fixed.zig").Fixed;
const message = @import("message.zig");
pub const Message = message.MessageUnion;
pub const Server = @import("Server.zig");
pub const wire = @import("wire.zig");

pub const ProtocolSide = enum { client, server };
test {
    @import("std").testing.refAllDecls(@This());
}
