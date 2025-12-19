const InterfaceMap = @This();

inner: std.StringArrayHashMapUnmanaged(Entry),

pub const empty = InterfaceMap{ .inner = .empty };

pub fn deinit(self: *InterfaceMap, gpa: Allocator) void {
    var it = self.inner.iterator();
    while (it.next()) |entry| {
        gpa.free(entry.key_ptr.*);
        entry.value_ptr.deinit(gpa);
    }
    self.inner.deinit(gpa);
}

pub fn get(self: *const InterfaceMap, interface: []const u8) !Entry {
    return self.inner.get(interface) orelse error.InterfaceNotFound;
}

pub fn put(
    self: *InterfaceMap,
    gpa: Allocator,
    protocol: *const Protocol,
    interface: *const Interface,
) !void {
    const key = try gpa.dupe(u8, interface.name);
    errdefer gpa.free(key);
    const value = try Entry.init(gpa, protocol, interface);
    errdefer value.deinit(gpa);

    try self.inner.put(gpa, key, value);
}

pub fn putRaw(
    self: *InterfaceMap,
    gpa: Allocator,
    interface: []const u8,
    protocol: []const u8,
    type_name: []const u8,
) !void {
    const key = try gpa.dupe(u8, interface);
    errdefer gpa.free(key);
    const proto_dup = try gpa.dupe(u8, protocol);
    errdefer gpa.free(proto_dup);
    const type_dup = try gpa.dupe(u8, type_name);
    errdefer gpa.free(type_dup);
    try self.inner.put(gpa, key, .{ .protocol = proto_dup, .type_name = type_dup });
}

pub const Entry = struct {
    protocol: []const u8,
    type_name: []const u8,

    pub fn init(
        gpa: Allocator,
        protocol: *const Protocol,
        interface: *const Interface,
    ) !Entry {
        const protocol_name = try gpa.dupe(u8, protocol.name);
        errdefer gpa.free(protocol_name);

        const type_name = try interface.typeName(gpa, protocol.prefix);
        errdefer gpa.free(type_name);

        return .{ .protocol = protocol_name, .type_name = type_name };
    }

    pub fn deinit(self: Entry, gpa: Allocator) void {
        gpa.free(self.protocol);
        gpa.free(self.type_name);
    }
};

const std = @import("std");
const Protocol = @import("Protocol.zig");
const Interface = @import("Interface.zig");
const Allocator = std.mem.Allocator;
