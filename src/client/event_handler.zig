pub const EventHandler = EventHandlerCustomProtocols(@import("client_protocol"));

pub fn EventHandlerCustomProtocols(comptime protocol: type) type {
    return struct {
        proxies: std.ArrayList(Proxy),

        pub const Proxy = struct {
            id: u32,
            interface: [:0]const u8,
        };

        pub fn initCapacity(gpa: Allocator, initial_capacity: usize) !EventHandler {
            return .{ .proxies = try .initCapacity(gpa, initial_capacity) };
        }

        pub fn initBuffered(buffer: []Proxy) EventHandler {
            return .{ .proxies = .initBuffer(buffer) };
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

        pub fn addObjectBounded(self: *EventHandler, object: anytype) !void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.appendBounded(proxy);
        }

        pub fn delObject(self: *EventHandler, object: anytype) void {
            const id = switch (@typeInfo(@TypeOf(object))) {
                .int => object,
                .@"enum" => object.getId(),
                else => @compileError("Unsupported type."),
            };

            for (self.proxies.items, 0..) |proxy, i| {
                if (proxy.id == id) {
                    _ = self.proxies.swapRemove(i);
                    return;
                }
            }
        }

        pub fn getNextEvent(self: *const EventHandler, connection: *Connection, buf: []u8) !?protocol.Event {
            return self.waitNextEventTimeout(connection, 0, buf);
        }

        pub fn waitNextEvent(self: *const EventHandler, connection: *Connection, buf: []u8) !protocol.Event {
            while (true) {
                if (try self.waitNextEventTimeout(connection, -1, buf)) |ev| return ev;
            }
        }

        pub fn waitNextEventTimeout(
            self: *const EventHandler,
            connection: *Connection,
            timeout: i32,
            buf: []u8,
        ) !?protocol.Event {
            _ = timeout;
            try connection.writer.flush();
            while (true) {
                var header: wire.Header = undefined;
                var iov = [1]std.posix.iovec{.{ .base = @ptrCast(&header), .len = @sizeOf(wire.Header) }};
                var control: [cmsg.space(20)]u8 = @splat(0);
                var msg = std.posix.msghdr{
                    .name = null,
                    .namelen = 0,
                    .iov = &iov,
                    .iovlen = 1,
                    .control = &control,
                    .controllen = cmsg.length(20),
                    .flags = 0,
                };
                if (std.os.linux.recvmsg(connection.handle, &msg, 0) <= 0) return error.ReadFailed;

                var read: usize = 0;

                while (read < header.length - 8) {
                    read += try std.posix.read(connection.handle, buf[read .. header.length - 8]);
                }

                for (self.proxies.items) |proxy| {
                    if (proxy.id == header.object) {
                        return deserializeEvent(header, proxy.interface, buf[0 .. header.length - 8], &msg);
                    }
                } else continue;
            }
        }
        fn deserializeEvent(
            header: wire.Header,
            target_interface: [:0]const u8,
            bytes: []const u8,
            msg: *const std.posix.msghdr,
        ) protocol.Event {
            inline for (@typeInfo(protocol.Event).@"union".fields) |field| {
                if (std.mem.eql(u8, field.name, target_interface)) {
                    inline for (@typeInfo(field.type).@"union".fields, 0..) |sub_field, i| {
                        if (i == header.opcode) {
                            var data: sub_field.type = wire.deserializeEventType(sub_field.type, bytes, msg);
                            @field(data, std.meta.fields(@TypeOf(data))[0].name) = @enumFromInt(header.object);
                            const sub_ev = @unionInit(field.type, sub_field.name, data);
                            const ev = @unionInit(protocol.Event, field.name, sub_ev);
                            return ev;
                        }
                    }
                }
            }
            @panic("Invalid opcode");
        }
    };
}

const std = @import("std");
const core = @import("core");
const wire = core.wire;
const log = std.log.scoped(.wayland_client);
const Allocator = std.mem.Allocator;
const Connection = core.Connection;
