const EventHandler = @This();

proxies: std.ArrayList(Proxy),

pub fn init(gpa: Allocator) !EventHandler {
    return .{ .proxies = try .initCapacity(gpa, 16) };
}

pub fn deinit(self: *EventHandler, gpa: Allocator) void {
    self.proxies.deinit(gpa);
}

pub fn addObject(self: *EventHandler, gpa: Allocator, object: anytype) !void {
    const proxy = Proxy{
        .id = object.getId(),
        .interface = @TypeOf(object).interface,
    };
    try self.proxies.append(gpa, proxy);
}

pub fn delObject(self: *EventHandler, object: anytype) !void {
    const id = object.getId();
    for (self.proxies.items, 0..) |proxy, i| {
        if (proxy.id == id) {
            _ = self.proxies.swapRemove(i);
            return;
        }
    }
    return error.ObjectNotFound;
}

pub fn waitNextEvent(self: *const EventHandler, connection: *Connection) !protocol.Event {
    while (true) {
        if (try self.waitNextEventTimeout(connection, -1)) |ev| return ev;
    }
}

pub fn waitNextEventTimeout(
    self: *const EventHandler,
    connection: *Connection,
    timeout: i32,
) !?protocol.Event {
    _ = timeout;
    while (true) {
        var header: wire.Header = undefined;
        _ = try std.posix.read(connection.handle, std.mem.asBytes(&header));
        var buffer: [4088]u8 = undefined;
        var read: usize = 0;
        while (read < header.length - 8) {
            read += try std.posix.read(connection.handle, buffer[read .. header.length - 8]);
        }
        for (self.proxies.items) |proxy| {
            if (proxy.id == header.object) {
                return deserializeEvent(header, proxy.interface, buffer[0 .. header.length - 8]);
            }
        } else continue;
    }
}

pub fn getNextEvent(self: *const EventHandler, connection: *Connection) !?protocol.Event {
    return self.waitNextEventTimeout(connection, 0);
}

const std = @import("std");
const core = @import("core");
const protocol = @import("protocol");
const wire = core.wire;
const log = std.log.scoped(.wayland_client);
const Allocator = std.mem.Allocator;
const Connection = core.Connection;

const Proxy = struct {
    id: u32,
    interface: [:0]const u8,
};

pub fn deserializeEvent(header: wire.Header, target_interface: [:0]const u8, bytes: []const u8) protocol.Event {
    _ = bytes;
    inline for (@typeInfo(protocol.Event).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, target_interface)) {
            inline for (@typeInfo(field.type).@"union".fields, 0..) |sub_field, i| {
                if (i == header.opcode) {
                    std.debug.print("{s}\n", .{@typeName(sub_field.type)});
                    return protocol.Event{ .xdg_wm_base = .{ .ping = undefined } };
                }
            }
        }
    }
    unreachable;
}
