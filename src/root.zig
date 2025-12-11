pub const protocol = @import("protocol.zig");
pub const DisplayConnection = @import("DisplayConnection.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
