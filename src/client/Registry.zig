const Registry = @This();

inner: wl.Registry,
globals: std.ArrayList(Global),

pub fn register(self: *Registry, gpa: Allocator, name: u32, interface: []const u8, version: u32) error{OutOfMemory}!void {
    try self.globals.append(gpa, .{ .name = name, .interface = try gpa.dupe(u8, interface), .version = version });
}

pub fn unregister(self: *Registry, gpa: Allocator, name: u32) error{NameNotRegistered}!void {
    for (self.globals.items, 0..) |global, i| {
        if (global.name == name) {
            const removed = self.globals.swapRemove(i);
            gpa.free(removed.interface);
        }
    }
}

pub fn bind(
    self: Registry,
    connection: *core.Connection,
    ida: core.IdAllocator,
    comptime T: type,
    version: T.Version,
) !?T {
    for (self.globals.items) |global| {
        if (global.interface == T.interface) {
            return try self.inner.bind(T, version, connection, ida);
        }
    }
    return null;
}

pub fn destroy(
    self: *Registry,
    gpa: Allocator,
    connection: *core.Connection,
    ida: core.IdAllocator,
) !void {
    if (try self.bind(connection, ida, wl.Fixes, .v1)) |fixes| {
        try fixes.destroyRegistry(connection, self.inner);
        try fixes.destroy(connection);
    }
    self.deinit(gpa);
}

pub fn deinit(self: *Registry, gpa: Allocator) void {
    for (self.globals.items) |global|
        gpa.free(global.interface);
    self.globals.deinit(gpa);
}

const std = @import("std");
const core = @import("core");
const wl = @import("protocol").wayland;
const Allocator = std.mem.Allocator;

const Global = struct {
    name: u32,
    interface: []const u8,
    version: u32,
};
