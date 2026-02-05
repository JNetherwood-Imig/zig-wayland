//! A simple API for interacting with the Wayland protocol.
//!
//! Includes both client and server components.
//!
//! Copyright © 2025 Jackson Netherwood-Imig.

pub const Fixed = @import("fixed.zig").Fixed;
pub const Server = @import("Server.zig");
pub const Message = message.MessageUnion;
pub const Connection = @import("Connection.zig");
pub const ProtocolSide = enum { client, server };
pub const Address = @import("Addresss.zig");
pub const wire = @import("wire.zig");

const message = @import("message.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
