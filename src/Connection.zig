const std = @import("std");

const ProtocolSide = @import("wayland_core.zig").ProtocolSide;
const Address = @import("Addresss.zig");
const wire = @import("wire.zig");
const cmsg = @import("cmsg.zig");

const log = std.log.scoped(.wayland_connection);

const Connection = @This();

stream: std.Io.net.Stream,

io: std.Io,
map: ObjectInterfaceMap,

data_in: Buffer(wire.libwayland_max_message_size, u8) = .{},
data_out: Buffer(wire.libwayland_max_message_size, u8) = .{},
fd_in: Buffer(wire.libwayland_max_message_args, std.posix.fd_t) = .{},
fd_out: Buffer(wire.libwayland_max_message_args, std.posix.fd_t) = .{},

next_id: u32 = wire.client_min_id,
id_free_list: std.ArrayList(u32) = .empty,
min_id: u32 = wire.client_min_id,
max_id: u32 = wire.client_max_id,

pub fn init(io: std.Io, gpa: std.mem.Allocator, addr: Address) !Connection {
    var map: ObjectInterfaceMap = try .init(gpa);
    errdefer map.deinit(gpa);

    const stream = try connectToAddress(io, addr);

    return Connection{
        .stream = stream,
        .io = io,
        .map = map,
    };
}

/// Takes ownership of Stream.
pub fn fromStream(
    io: std.Io,
    gpa: std.mem.Allocator,
    stream: std.Io.net.Stream,
    side: ProtocolSide,
) !Connection {
    return Connection{
        .io = io,
        .map = try .init(gpa),
        .stream = stream,
        .next_id = switch (side) {
            .client => wire.client_min_id,
            .server => wire.server_min_id,
        },
        .min_id = switch (side) {
            .client => wire.client_min_id,
            .server => wire.server_min_id,
        },
        .max_id = switch (side) {
            .client => wire.client_max_id,
            .server => wire.server_max_id,
        },
    };
}

pub fn deinit(self: *Connection, gpa: std.mem.Allocator) void {
    self.id_free_list.deinit(gpa);
    self.map.deinit(gpa);
    self.stream.close(self.io);
    self.* = undefined;
}

pub fn sendMessage(
    self: *Connection,
    sender_id: u32,
    comptime len: usize,
    comptime opcode: u16,
    args: anytype,
    fds: []const std.posix.fd_t,
) !void {
    var buf: [len]u8 = undefined;
    const serialized = try wire.serializeMessage(&buf, sender_id, opcode, args);
    const res1 = self.data_out.putMany(buf[0..serialized]);
    const res2 = self.putFds(fds);
    if (res1) |_| {} else |_| {
        @branchHint(.unlikely);
        try self.flush();
        try self.data_out.putMany(buf[0..serialized]);
    }

    if (res2) |_| {} else |err| switch (err) {
        error.OutOfSpace => {
            @branchHint(.unlikely);
            try self.flush();
            try self.putFds(fds);
        },
        else => |e| return e,
    }
}

pub fn nextMessage(self: *Connection, comptime Message: type, timeout: ?std.Io.Timeout) !Message {
    const deadline: ?std.Io.Clock.Timestamp = if (timeout) |t|
        try t.toDeadline(self.io)
    else
        .{ .clock = .awake, .raw = .zero };

    self.flush() catch |err| switch (err) {
        error.SocketUnconnected => {},
        else => |e| return e,
    };

    outer: while (true) {
        const header = self.peekHeader() orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };

        if (header.length > wire.libwayland_max_message_size)
            return error.MessageTooLong;

        const message = self.data_in.peek(header.length) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };
        const body = message[@sizeOf(wire.Header)..];

        const interface = try self.map.getInterface(header.object);
        return try self.deserializeMessage(Message, header, interface, body) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };
    }
}

pub fn createObject(self: *Connection, comptime T: type, gpa: std.mem.Allocator) !T {
    const id = id: {
        if (self.id_free_list.pop()) |id| break :id id;

        if (self.next_id > self.max_id) {
            @branchHint(.unlikely);
            return error.OutOfIds;
        }

        defer self.next_id += 1;
        break :id self.next_id;
    };

    try self.map.add(gpa, id, T.interface);

    return @enumFromInt(id);
}

pub fn releaseObject(self: *Connection, gpa: std.mem.Allocator, id: u32) !void {
    if (id == self.next_id - 1)
        self.next_id -= 1
    else
        try self.id_free_list.append(gpa, id);
    try self.map.del(id);
}

pub fn flush(self: *Connection) !void {
    if (self.data_out.end == 0) return;

    const data = self.data_out.data[self.data_out.start..self.data_out.end];
    var iov = [1]std.posix.iovec_const{.{ .base = data.ptr, .len = data.len }};

    const fds = self.fd_out.data[self.fd_out.start..self.fd_out.end];
    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 = undefined;
    std.mem.bytesAsValue(cmsg.Header, control[0..@sizeOf(cmsg.Header)]).* = .{
        .len = cmsg.length(fds.len),
    };
    const dest = std.mem.bytesAsSlice(
        std.posix.fd_t,
        control[@sizeOf(cmsg.Header)..][0..(fds.len * @sizeOf(std.posix.fd_t))],
    );
    @memcpy(dest, fds);

    const msg = std.posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = &control,
        .controllen = @intCast(cmsg.length(fds.len)),
        .flags = 0,
    };

    const rc = std.posix.system.sendmsg(self.stream.socket.handle, &msg, 0);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .PIPE => return error.SocketUnconnected,
        else => |err| return std.posix.unexpectedErrno(err),
    }

    for (fds) |fd| _ = std.posix.system.close(fd);
    self.data_out.start = 0;
    self.data_out.end = 0;
    self.fd_out.start = 0;
    self.fd_out.end = 0;
}

fn putFds(self: *Connection, fds: []const std.posix.fd_t) !void {
    if (self.fd_out.end + fds.len >= self.fd_out.data.len)
        return error.OutOfSpace;

    for (fds) |fd| {
        const rc = std.posix.system.dup(fd);
        const dup: std.posix.fd_t = switch (std.posix.errno(rc)) {
            .SUCCESS => @intCast(rc),
            else => |err| return std.posix.unexpectedErrno(err),
        };
        self.fd_out.put(dup) catch unreachable;
    }
}

fn peekHeader(self: *const Connection) ?wire.Header {
    const bytes = self.data_in.peek(@sizeOf(wire.Header)) orelse return null;
    return std.mem.bytesToValue(wire.Header, bytes);
}

fn readIncoming(self: *Connection, deadline: ?std.Io.Clock.Timestamp) !void {
    self.data_in.shiftToStart();
    self.fd_in.shiftToStart();

    const timeout_ms: i32 = if (deadline) |d| ms: {
        const remaining = try d.durationFromNow(self.io);
        break :ms if (remaining.raw.nanoseconds <= 0) 0 else @intCast(remaining.raw.toMilliseconds());
    } else -1;

    var pfds = [1]std.posix.pollfd{.{
        .fd = self.stream.socket.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    const count = try std.posix.poll(&pfds, timeout_ms);

    if (count == 0) return error.TimedOut;

    const data = self.data_in.data[self.data_in.end..];
    var iov = [1]std.posix.iovec{.{ .base = data.ptr, .len = data.len }};

    var control: [cmsg.space(wire.libwayland_max_message_args)]u8 align(@alignOf(cmsg.Header)) = undefined;

    var msg = std.posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = &control,
        .controllen = control.len,
        .flags = 0,
    };

    const rc = std.posix.system.recvmsg(self.stream.socket.handle, &msg, std.posix.system.MSG.DONTWAIT);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .PIPE => return error.SocketUnconnected,
        else => |err| return std.posix.unexpectedErrno(err),
    }

    if (rc == 0) return error.ConnectionClosed;

    self.data_in.end += @intCast(rc);

    var header = cmsg.firstHeader(&msg);
    while (header) |head| {
        const fd_bytes: []align(@alignOf(std.posix.fd_t)) const u8 = @alignCast(cmsg.data(head));
        const fds = std.mem.bytesAsSlice(std.posix.fd_t, fd_bytes);
        try self.fd_in.putMany(fds);
        header = cmsg.nextHeader(&msg, head);
    }
}

fn deserializeMessage(
    self: *Connection,
    comptime Message: type,
    header: wire.Header,
    interface: [:0]const u8,
    body: []const u8,
) !?Message {
    // This is arbitrary, but works for now.
    @setEvalBranchQuota(10000);

    const ti = @typeInfo(Message).@"union";
    inline for (ti.fields) |field| if (std.mem.eql(u8, field.name, interface)) {
        const sub_fields = @typeInfo(field.type).@"union".fields;
        switch (header.opcode) {
            inline 0...sub_fields.len - 1 => |i| {
                const sub_field = sub_fields[i];

                const fd_count = countFds(sub_field.type);
                const fds = self.fd_in.peek(fd_count) orelse return null;

                self.data_in.discard(header.length) catch unreachable;
                self.fd_in.discard(fd_count) catch unreachable;

                var message = try wire.deserializeMessage(sub_field.type, body, fds);

                const object_self_field = std.meta.fields(@TypeOf(message))[0];
                @field(message, object_self_field.name) = @enumFromInt(header.object);

                const interface_message = @unionInit(field.type, sub_field.name, message);
                return @unionInit(Message, field.name, interface_message);
            },
            else => return error.InvalidOpcode,
        }
    };

    @panic("Interface not present in generated message union.");
}

fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (T._signature) |byte| if (byte == 'd') {
        count += 1;
    };
    return count;
}

fn connectToAddress(io: std.Io, addr: Address) !std.Io.net.Stream {
    return switch (addr.info) {
        .sock => |sock| std.Io.net.Stream{ .socket = .{
            .handle = sock,
            .address = .{ .ip4 = .loopback(0) },
        } },
        .path => |path| stream: {
            const un = std.Io.net.UnixAddress.init(std.mem.sliceTo(&path, 0)) catch unreachable;
            break :stream un.connect(io);
        },
    };
}

fn Buffer(comptime length: usize, comptime T: type) type {
    return struct {
        const Self = @This();

        data: [length]T = undefined,
        start: usize = 0,
        end: usize = 0,

        pub fn put(self: *Self, item: T) !void {
            if (self.end + 1 >= self.data.len)
                return error.OutOfSpace;
            self.data[self.end] = item;
            self.end += 1;
        }

        pub fn putMany(self: *Self, data: []const T) !void {
            if (self.end + data.len >= self.data.len)
                return error.OutOfSpace;
            @memcpy(self.data[self.end..][0..data.len], data);
            self.end += data.len;
        }

        pub fn peek(self: *const Self, n: usize) ?[]const T {
            if (n > self.end - self.start) return null;
            return self.data[self.start..][0..n];
        }

        pub fn discard(self: *Self, n: usize) !void {
            if (n > self.end - self.start) return error.DiscardTooLong;
            self.start += n;
            if (self.start == self.end) {
                self.start = 0;
                self.end = 0;
            }
        }

        pub fn shiftToStart(self: *Self) void {
            if (self.start == 0) return;
            const len = self.end - self.start;
            @memmove(self.data[0..len], self.data[self.start..self.end]);
            self.start = 0;
            self.end = len;
        }
    };
}

const ObjectInterfaceMap = struct {
    client: []?[:0]const u8,
    server: []?[:0]const u8,

    pub fn init(gpa: std.mem.Allocator) !ObjectInterfaceMap {
        var client_buf = try gpa.alloc(?[:0]const u8, 16);
        errdefer gpa.free(client_buf);
        @memset(client_buf, null);
        client_buf[0] = "wl_display";

        const server_buf = try gpa.alloc(?[:0]const u8, 4);

        return ObjectInterfaceMap{ .client = client_buf, .server = server_buf };
    }

    pub fn deinit(self: *ObjectInterfaceMap, gpa: std.mem.Allocator) void {
        gpa.free(self.client);
        gpa.free(self.server);
    }

    pub fn add(
        self: *ObjectInterfaceMap,
        gpa: std.mem.Allocator,
        id: u32,
        interface: [:0]const u8,
    ) !void {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        try self.ensureCapacity(gpa, idx, side);

        const interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (interfaces[idx] != null) {
            @branchHint(.unlikely);
            return error.ObjectAlreadyExists;
        }
        interfaces[idx] = interface;
    }

    pub fn del(self: *ObjectInterfaceMap, id: u32) !void {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx >= interfaces.len or interfaces[idx] == null) {
            @branchHint(.unlikely);
            log.err("Delete object: invalid object id: {d}.", .{id});
            return error.InvalidObject;
        }
        interfaces[idx] = null;
    }

    pub fn getInterface(self: *ObjectInterfaceMap, id: u32) ![:0]const u8 {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        const interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };
        return interfaces[idx] orelse error.InvalidID;
    }

    fn getSide(id: u32) !ProtocolSide {
        return switch (id) {
            1, wire.client_min_id...wire.client_max_id => .client,
            wire.server_min_id...wire.server_max_id => .server,
            else => error.InvalidID,
        };
    }

    fn getIdx(id: u32, side: ProtocolSide) usize {
        return switch (side) {
            .client => id - 1,
            .server => id - wire.server_min_id,
        };
    }

    fn ensureCapacity(
        self: *ObjectInterfaceMap,
        gpa: std.mem.Allocator,
        idx: usize,
        side: ProtocolSide,
    ) error{ InvalidObject, OutOfMemory }!void {
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx > interfaces.len) return error.InvalidObject;

        if (idx == interfaces.len) {
            const new_capacity = interfaces.len * 2;
            const new_memory = gpa.remap(interfaces, new_capacity) orelse mem: {
                const new_memory = try gpa.alloc(?[:0]const u8, new_capacity);
                @memcpy(new_memory[0..interfaces.len], interfaces);
                gpa.free(interfaces);
                break :mem new_memory;
            };

            interfaces.ptr = new_memory.ptr;
            const old_len = interfaces.len;
            interfaces.len = new_memory.len;
            for (old_len..interfaces.len) |i|
                interfaces[i] = null;
        }
    }
};
