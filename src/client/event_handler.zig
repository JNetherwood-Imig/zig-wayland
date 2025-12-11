pub fn EventHandler(comptime protocol: type) type {
    return struct {
        const Self = @This();

        proxies: std.ArrayList(Proxy),

        pub const Proxy = struct {
            id: u32,
            interface: [:0]const u8,
        };

        pub fn initCapacity(gpa: Allocator, initial_capacity: usize) !Self {
            return .{ .proxies = try .initCapacity(gpa, initial_capacity) };
        }

        pub fn initBuffered(buffer: []Proxy) Self {
            return .{ .proxies = .initBuffer(buffer) };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.proxies.deinit(gpa);
        }

        pub fn addObject(self: *Self, gpa: Allocator, object: anytype) !void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.append(gpa, proxy);
        }

        pub fn addObjectBounded(self: *Self, object: anytype) !void {
            const proxy = Proxy{
                .id = object.getId(),
                .interface = @TypeOf(object).interface,
            };
            try self.proxies.appendBounded(proxy);
        }

        pub fn delObject(self: *Self, object: anytype) void {
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

        pub fn getNextEvent(self: *const Self, connection: *Connection) !?protocol.Event {
            return self.nextEvent(connection, false);
        }

        pub fn waitNextEvent(self: *const Self, connection: *Connection) !protocol.Event {
            while (true) {
                if (try self.nextEvent(connection, true)) |ev| return ev;
            }
        }

        fn nextEvent(self: *const Self, conn: *Connection, wait: bool) !?protocol.Event {
            conn.writer.flush() catch |e| switch (e) {
                error.BrokenPipe => {},
                else => return e,
            };

            while (true) {
                const header = conn.reader.nextHeader() orelse {
                    if (!try conn.pollEvents(wait)) return null;
                    continue;
                };
                std.log.debug("Received event {any}.", .{header});
                var buf: [4096]u8 = undefined;
                std.debug.assert(conn.reader.getData(buf[0 .. header.length - 8]) == header.length - 8);
                for (self.proxies.items) |proxy| {
                    if (proxy.id == header.object) {
                        return deserializeEvent(header, proxy.interface, buf[0 .. header.length - 8], &.{});
                    }
                }
            }
        }

        fn countFds(comptime T: type) usize {
            var count: usize = 0;
            for (T._signature) |byte| {
                if (byte == 'f') count += 1;
            }
            return count;
        }

        fn deserializeEvent(
            header: wire.Header,
            target_interface: [:0]const u8,
            bytes: []const u8,
            fds: []const std.posix.fd_t,
        ) protocol.Event {
            inline for (@typeInfo(protocol.Event).@"union".fields) |field| {
                if (std.mem.eql(u8, field.name, target_interface)) {
                    const sub_fields = @typeInfo(field.type).@"union".fields;
                    switch (header.opcode) {
                        inline 0...sub_fields.len - 1 => |i| {
                            const sub_field = sub_fields[i];
                            var data: sub_field.type = wire.deserializeEventType(sub_field.type, bytes, fds);
                            @field(data, std.meta.fields(@TypeOf(data))[0].name) = @enumFromInt(header.object);
                            const sub_ev = @unionInit(field.type, sub_field.name, data);
                            const ev = @unionInit(protocol.Event, field.name, sub_ev);
                            return ev;
                        },
                        else => @panic("Invalid opcode."),
                    }
                    // inline for (@typeInfo(field.type).@"union".fields, 0..) |sub_field, i| {
                    //     if (i == header.opcode) {
                    //         var data: sub_field.type = wire.deserializeEventType(sub_field.type, bytes, fds);
                    //         @field(data, std.meta.fields(@TypeOf(data))[0].name) = @enumFromInt(header.object);
                    //         const sub_ev = @unionInit(field.type, sub_field.name, data);
                    //         const ev = @unionInit(protocol.Event, field.name, sub_ev);
                    //         return ev;
                    //     }
                    // }
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
const cmsg = @import("cmsg.zig");
const Allocator = std.mem.Allocator;
const Connection = core.Connection;
