const std = @import("std");
const sys = std.posix.system;

const Address = @import("address.zig").Address;
const cmsg = @import("cmsg.zig");
const ProtocolSide = @import("wayland_core.zig").ProtocolSide;
const wire = @import("wire.zig");

const log = std.log.scoped(.wayland);
const Connection = @This();

stream: std.Io.net.Stream,

io: std.Io,
gpa: std.mem.Allocator,
map: ObjectMap,

data_in: Buffer(wire.libwayland_max_message_size, u8) = .{},
data_out: Buffer(wire.libwayland_max_message_size, u8) = .{},
fd_in: Buffer(wire.libwayland_max_message_args, std.posix.fd_t) = .{},
fd_out: Buffer(wire.libwayland_max_message_args, std.posix.fd_t) = .{},

next_id: u32,
min_id: u32,
max_id: u32,
id_free_list: std.ArrayList(u32) = .empty,

next_serial: u32 = 0,

/// Last message header which was received. Can be used for debugging purposes.
last_header: ?wire.Header = null,

pub const InitError = std.Io.net.UnixAddress.ConnectError || error{OutOfMemory};

/// Creates a new `Connection` connected to `addr`.
/// Stores `io` and `gpa` for internal use.
pub fn init(io: std.Io, gpa: std.mem.Allocator, addr: Address) !Connection {
    var map: ObjectMap = try .init(gpa);
    errdefer map.deinit(gpa);

    const stream = try connectToAddress(io, addr);

    return Connection{
        .stream = stream,
        .io = io,
        .gpa = gpa,
        .map = map,
        .next_id = wire.client_min_id + 1,
        .min_id = wire.client_min_id,
        .max_id = wire.client_max_id,
    };
}

/// Deinitializes all internal resources.
pub fn deinit(self: *Connection) void {
    for (self.fd_out.slice()) |fd| _ = std.posix.system.close(fd);
    for (self.fd_in.slice()) |fd| _ = std.posix.system.close(fd);
    self.id_free_list.deinit(self.gpa);
    self.map.deinit(self.gpa);
    self.stream.close(self.io);
    self.* = undefined;
}

/// Creates a new `Connection` from `stream`
/// Takes ownership of `stream`.
/// Stores `io` and `gpa` for internal use.
pub fn fromStream(
    io: std.Io,
    gpa: std.mem.Allocator,
    stream: std.Io.net.Stream,
    side: ProtocolSide,
) error{OutOfMemory}!Connection {
    return Connection{
        .io = io,
        .gpa = gpa,
        .map = try .init(gpa),
        .stream = stream,
        .next_id = switch (side) {
            .client => wire.client_min_id + 1,
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

/// Convenience method for accessing stream handle.
pub inline fn getFd(self: *const Connection) std.posix.fd_t {
    return self.stream.socket.handle;
}

/// Gets next available serial for messages
pub fn nextSerial(self: *Connection) u32 {
    defer self.next_serial +%= 1;
    return self.next_serial;
}

/// Sets the user data pointer for an object
pub fn setObjectUserData(
    self: *Connection,
    object: u32,
    data: ?*anyopaque,
    destructor: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!void,
) error{InvalidID}!void {
    const entry = try self.map.getEntry(object);
    entry.user_data = data;
    entry.destroyUserDataCallback = destructor;
}

/// Gets the user data for an object
pub fn getObjectUserData(self: *Connection, object: u32) error{InvalidID}!?*anyopaque {
    const entry = try self.map.getEntry(object);
    return entry.user_data;
}

/// Runs the destructor for an object's user data
pub fn destroyObjectUserData(self: *Connection, gpa: std.mem.Allocator, object: u32) anyerror!void {
    const entry = try self.map.getEntry(object);
    if (entry.user_data) |data| if (entry.destroyUserDataCallback) |destroyFn| try destroyFn(data, gpa);
}

pub const SendError = wire.SerializeError || FlushError || PutFdsError;

/// INTERNAL USE ONLY
/// Serializes and sends a message across the wire.
pub fn sendMessage(
    self: *Connection,
    sender_id: u32,
    comptime len: usize,
    comptime opcode: u16,
    args: anytype,
    fds: []const std.posix.fd_t,
) SendError!void {
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

pub const NextMessageError = FlushError ||
    ReadIncomingError ||
    DeserializeMessageError ||
    error{ MessageTooLong, InvalidID };

/// Waits for the next available message and fills out a `Message` union.
/// `timeout` can be `.none`, `.{ .duration = [duration] }`, `.{ .deadline = [deadline] }`,
/// or `null` for instant timeout.
pub fn nextMessage(self: *Connection, comptime Message: type, timeout: ?std.Io.Timeout) NextMessageError!Message {
    const deadline = if (timeout) |t| t.toDeadline(self.io).toTimestamp(self.io) else std.Io.Clock.Timestamp{ .clock = .awake, .raw = .zero };

    try self.flush();

    outer: while (true) {
        const header = self.peekHeader() orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };

        if (header.length > wire.libwayland_max_message_size)
            return error.MessageTooLong;

        const data = self.data_in.peek(header.length) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };
        const body = data[@sizeOf(wire.Header)..];

        const interface = try self.map.getInterface(header.object);
        const message = try self.deserializeMessage(Message, header, interface, body) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };

        self.last_header = header;

        return message;
    }
}

pub const CreateObjectError = error{ OutOfMemory, OutOfIds, InvalidID, ObjectAlreadyExists };

/// Allocates a new id by either popping from the free-list, or incrementing the value of `next_id`
/// and returns a new `T`.
/// The resulting object is addded to the internal object-interface map, which may cause an allocation.
pub fn createObject(self: *Connection, comptime T: type) CreateObjectError!T {
    const id = id: {
        if (self.id_free_list.pop()) |id| break :id id;

        if (self.next_id > self.max_id) {
            @branchHint(.unlikely);
            return error.OutOfIds;
        }

        defer self.next_id += 1;
        break :id self.next_id;
    };

    try self.map.add(self.gpa, id, T.interface);

    return @enumFromInt(id);
}

pub const ReleaseObjectError = error{ OutOfMemory, InvalidID };

/// Removes an object from the connection's internal object-interface map and either
/// appends the free'd id to the free-list (may allocate) or decrements the `next_id` if possible.
pub fn releaseObject(self: *Connection, id: u32) ReleaseObjectError!void {
    if (id == self.next_id - 1)
        self.next_id -= 1
    else
        try self.id_free_list.append(self.gpa, id);
    try self.map.del(id);
}

pub const RegisterObjectError = error{ OutOfMemory, InvalidID, ObjectAlreadyExists };

/// Adds an externally created object (created by opposite end of wire)
/// to the connection's internal object-interface map.
/// `interface` should point to static memory, likely from codegen.
pub inline fn registerObject(self: *Connection, id: u32, interface: [:0]const u8) RegisterObjectError!void {
    try self.map.add(self.gpa, id, interface);
}

pub const FlushError = error{ ConnectionClosed, OutOfMemory, Unexpected };

pub fn flush(self: *Connection) FlushError!void {
    if (self.data_out.end == 0) return;

    const data = self.data_out.slice();
    var iov = [1]std.posix.iovec_const{.{ .base = data.ptr, .len = data.len }};

    const fds = self.fd_out.slice();
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

    const sent: usize = while (true) {
        const rc = sys.sendmsg(self.stream.socket.handle, &msg, 0);
        switch (std.posix.errno(rc)) {
            // We ignore EPIPE and ECONNRESET so as to not crash the application, allowing the user
            // to gracefully handle being killed by the server.
            .SUCCESS => break @intCast(rc),
            .PIPE, .CONNRESET => break 0,

            .NOBUFS, .NOMEM => return error.OutOfMemory,

            .AGAIN => unreachable,
            .AFNOSUPPORT => unreachable,
            .BADF => unreachable,
            .INTR => continue,
            .INVAL => unreachable,
            .MSGSIZE => unreachable,
            .NOTCONN => unreachable,
            .NOTSOCK => unreachable,
            .OPNOTSUPP => unreachable,
            .IO => unreachable,
            .LOOP => unreachable,
            .NAMETOOLONG => unreachable,
            .NOENT => unreachable,
            .NOTDIR => unreachable,
            .ACCES => unreachable,
            .DESTADDRREQ => unreachable,
            .HOSTUNREACH => unreachable,
            .ISCONN => unreachable,
            .NETDOWN => unreachable,
            .NETUNREACH => unreachable,

            else => |err| return std.posix.unexpectedErrno(err),
        }
    };

    if (sent == 0) return error.ConnectionClosed;

    for (fds) |fd| _ = std.posix.system.close(fd);

    self.data_out.start = 0;
    self.data_out.end = 0;
    self.fd_out.start = 0;
    self.fd_out.end = 0;
}

const PutFdsError = error{ OutOfSpace, Unexpected };

fn putFds(self: *Connection, fds: []const std.posix.fd_t) PutFdsError!void {
    if (self.fd_out.end + fds.len >= self.fd_out.data.len)
        return error.OutOfSpace;

    for (fds) |fd| {
        const rc = sys.dup(fd);
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

const ReadIncomingError = std.posix.PollError || error{ ConnectionClosed, Timeout, OutOfMemory, OutOfSpace };

/// Try to read incoming data from the socket, returning error.Timeout if deadline is passed
fn readIncoming(self: *Connection, deadline: ?std.Io.Clock.Timestamp) ReadIncomingError!void {
    self.data_in.shiftToStart();
    self.fd_in.shiftToStart();

    const timeout_ms: i32 = if (deadline) |d| ms: {
        const remaining_ms = d.durationFromNow(self.io).raw.toMilliseconds();
        if (remaining_ms <= 0) return error.Timeout;
        break :ms @intCast(remaining_ms);
    } else -1;

    var pfd = [1]std.posix.pollfd{.{
        .fd = self.stream.socket.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    const count = try std.posix.poll(&pfd, timeout_ms);
    if (count == 0) return error.Timeout;

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

    const read: usize = while (true) {
        const rc = sys.recvmsg(self.stream.socket.handle, &msg, sys.MSG.DONTWAIT);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break @intCast(rc),

            .AGAIN => continue,
            .INTR => continue,

            .CONNRESET, .PIPE => return error.ConnectionClosed,
            .TIMEDOUT => return error.Timeout,
            .NOBUFS, .NOMEM => return error.OutOfMemory,

            .BADF => unreachable,
            .INVAL => unreachable,
            .MSGSIZE => unreachable,
            .NOTCONN => unreachable,
            .NOTSOCK => unreachable,
            .OPNOTSUPP => unreachable,
            .IO => unreachable,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    };

    if (read == 0) return error.ConnectionClosed;

    self.data_in.end += read;

    var header = cmsg.firstHeader(&msg);
    while (header) |head| {
        const fd_bytes: []align(@alignOf(std.posix.fd_t)) const u8 = @alignCast(cmsg.data(head));
        const fds = std.mem.bytesAsSlice(std.posix.fd_t, fd_bytes);
        try self.fd_in.putMany(fds);
        header = cmsg.nextHeader(&msg, head);
    }
}

const DeserializeMessageError = wire.DeserializeError ||
    RegisterObjectError ||
    error{ UnsupportedInterface, InvalidOpcode };

fn deserializeMessage(
    self: *Connection,
    comptime Message: type,
    header: wire.Header,
    interface: [:0]const u8,
    body: []const u8,
) DeserializeMessageError!?Message {
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

                const InnerType = sub_field.type;
                var message = try wire.deserializeMessage(InnerType, body, fds);
                populateRecipientField(InnerType, &message, header);
                try self.updateMap(InnerType, message);

                const interface_message = @unionInit(field.type, sub_field.name, message);
                return @unionInit(Message, field.name, interface_message);
            },
            else => return error.InvalidOpcode,
        }
    };

    return error.UnsupportedInterface;
}

fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (T._signature) |byte| if (byte == 'd') {
        count += 1;
    };
    return count;
}

fn populateRecipientField(comptime T: type, message: *T, header: wire.Header) void {
    const field_name = @typeInfo(T).@"struct".fields[0].name;
    @field(message, field_name) = @enumFromInt(header.object);
}

fn updateMap(self: *Connection, comptime T: type, message: T) !void {
    const signature: []const u8 = T._signature;
    if (signature.len == 0) return;
    const fields = @typeInfo(T).@"struct".fields[1..];

    inline for (signature, fields) |sig_byte, field| if (sig_byte == 'n') {
        const id: u32 = @intFromEnum(@field(message, field.name));
        const interface: [:0]const u8 = field.type.interface;
        try self.registerObject(id, interface);
    };
}

fn connectToAddress(io: std.Io, addr: Address) std.Io.net.UnixAddress.ConnectError!std.Io.net.Stream {
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

        pub const PutError = error{OutOfSpace};

        pub fn put(self: *Self, item: T) PutError!void {
            if (self.end + 1 >= self.data.len)
                return error.OutOfSpace;
            self.data[self.end] = item;
            self.end += 1;
        }

        pub fn putMany(self: *Self, data: []const T) PutError!void {
            if (self.end + data.len >= self.data.len)
                return error.OutOfSpace;
            @memcpy(self.data[self.end..][0..data.len], data);
            self.end += data.len;
        }

        pub fn peek(self: *const Self, n: usize) ?[]const T {
            if (n > self.end - self.start) return null;
            return self.data[self.start..][0..n];
        }

        pub const DiscardError = error{DiscardTooLong};

        pub fn discard(self: *Self, n: usize) DiscardError!void {
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

        pub fn slice(self: *Self) []T {
            return self.data[self.start..self.end];
        }
    };
}

const ObjectMap = struct {
    client: []?Entry,
    server: []?Entry,

    pub const Entry = struct {
        interface: [:0]const u8,
        user_data: ?*anyopaque = null,
        destroyUserDataCallback: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!void = null,

        pub inline fn destroyUserData(self: Entry, gpa: std.mem.Allocator) anyerror!void {
            if (self.user_data) |data| if (self.destroyUserDataCallback) |destructor| try destructor(data, gpa);
        }
    };

    const initial_capacity = 16;

    pub fn init(gpa: std.mem.Allocator) error{OutOfMemory}!ObjectMap {
        var client_buf = try gpa.alloc(?Entry, initial_capacity);
        errdefer gpa.free(client_buf);
        @memset(client_buf, null);
        client_buf[0] = .{ .interface = "wl_display" };

        return ObjectMap{ .client = client_buf, .server = &.{} };
    }

    pub fn deinit(self: *ObjectMap, gpa: std.mem.Allocator) void {
        for (self.client) |maybe_entry| if (maybe_entry) |entry| entry.destroyUserData(gpa) catch {};
        for (self.server) |maybe_entry| if (maybe_entry) |entry| entry.destroyUserData(gpa) catch {};
        gpa.free(self.client);
        gpa.free(self.server);
    }

    pub fn add(
        self: *ObjectMap,
        gpa: std.mem.Allocator,
        id: u32,
        interface: [:0]const u8,
    ) error{ OutOfMemory, InvalidID, ObjectAlreadyExists }!void {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        try self.ensureCapacity(gpa, idx, side);

        const entries = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (entries[idx] != null) {
            @branchHint(.unlikely);
            return error.ObjectAlreadyExists;
        }
        entries[idx] = .{ .interface = interface };
    }

    pub fn del(self: *ObjectMap, id: u32) error{InvalidID}!void {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        var entries = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx >= entries.len or entries[idx] == null) {
            @branchHint(.unlikely);
            log.err("Delete object: invalid object id: {d}.", .{id});
            return error.InvalidID;
        }
        entries[idx] = null;
    }

    pub fn getEntry(self: *ObjectMap, id: u32) error{InvalidID}!*Entry {
        const side = try getSide(id);
        const idx = getIdx(id, side);
        const entries = switch (side) {
            .client => self.client,
            .server => self.server,
        };
        return if (entries[idx]) |*ent| ent else error.InvalidID;
    }

    pub fn getInterface(self: *ObjectMap, id: u32) error{InvalidID}![:0]const u8 {
        return (try self.getEntry(id)).interface;
    }

    fn getSide(id: u32) error{InvalidID}!ProtocolSide {
        return switch (id) {
            wire.client_min_id...wire.client_max_id => .client,
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
        self: *ObjectMap,
        gpa: std.mem.Allocator,
        idx: usize,
        side: ProtocolSide,
    ) error{ InvalidID, OutOfMemory }!void {
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx > interfaces.len) return error.InvalidID;

        if (idx == interfaces.len) {
            const new_capacity = if (interfaces.len == 0) initial_capacity else interfaces.len * 2;
            const new_memory = gpa.remap(interfaces, new_capacity) orelse mem: {
                const new_memory = try gpa.alloc(?Entry, new_capacity);
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
