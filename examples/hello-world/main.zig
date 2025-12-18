const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wayland_client_protocol");
const xdg = @import("xdg_shell_client_protocol");
const Event = wayland.EventUnion(.{ wl, xdg });

pub fn main() !void {
    inline for (@typeInfo(Event).@"union".fields) |top_field| {
        std.debug.print("{s}: {s}\n", .{ top_field.name, @typeName(top_field.type) });
        inline for (@typeInfo(top_field.type).@"union".fields) |sub_field| {
            std.debug.print("\t{s}: {s}\n", .{ sub_field.name, @typeName(sub_field.type) });
            inline for (@typeInfo(sub_field.type).@"struct".fields) |ev_field| {
                std.debug.print("\t\t{s}: {s}\n", .{ ev_field.name, @typeName(ev_field.type) });
            }
        }
    }
}
