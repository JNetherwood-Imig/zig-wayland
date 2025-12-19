const Request = @This();

name: []const u8,
type: enum { none, destructor } = .none,
since: u32,
deprecated_since: ?u32,
description: ?Description,
args: std.ArrayList(Arg),

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Request {
    var name: ?[]const u8 = null;
    errdefer if (name) |n| gpa.free(n);
    var is_destructor: bool = false;
    var since: u32 = 1;
    var deprecated_since: ?u32 = null;

    for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);

        if (std.mem.eql(u8, attrib, "name"))
            name = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "type"))
            is_destructor = std.mem.eql(u8, reader.attributeValueRaw(i), "destructor")
        else if (std.mem.eql(u8, attrib, "since"))
            since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else if (std.mem.eql(u8, attrib, "deprecated-since"))
            deprecated_since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else
            continue;
    }

    var description: ?Description = null;
    errdefer if (description) |*desc| desc.deinit(gpa);

    var args = try std.ArrayList(Arg).initCapacity(gpa, 4);
    errdefer {
        for (args.items) |*arg| arg.deinit(gpa);
        args.deinit(gpa);
    }

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "request"))
                return error.UnexpectedElementEnd;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (std.mem.eql(u8, elem, "description"))
                description = try Description.parse(gpa, reader)
            else if (std.mem.eql(u8, elem, "arg")) {
                var arg = try Arg.parse(gpa, reader);
                errdefer arg.deinit(gpa);
                try args.append(gpa, arg);
            } else return error.UnexpectedElement;
        },
        else => continue,
    } else |err| return err;

    return .{
        .name = name orelse return error.NameNotFound,
        .type = if (is_destructor) .destructor else .none,
        .since = since,
        .deprecated_since = deprecated_since,
        .description = description,
        .args = args,
    };
}

pub fn deinit(self: *Request, gpa: Allocator) void {
    gpa.free(self.name);
    if (self.description) |*desc| desc.deinit(gpa);
    for (self.args.items) |*arg| arg.deinit(gpa);
    self.args.deinit(gpa);
}

pub fn write(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    interface: []const u8,
    opcode: usize,
) !void {
    const parent_interface_entry = try map.get(interface);

    const fn_name = try self.fnName(gpa);
    defer gpa.free(fn_name);

    const max_length = self.calculateMaxLength();
    try writer.print("\n\tpub const {s}_request_opcode = {d};\n", .{ self.name, opcode });
    try writer.print("\tpub const {s}_request_length = {d};\n\n", .{ self.name, max_length });

    if (self.description) |d| try d.write(writer, "\t/// ");
    try for (self.args.items) |arg| switch (arg.type) {
        .new_id => break self.writeConstructor(gpa, writer, map, parent_interface_entry.type_name, fn_name),
        .any_new_id => break try self.writeGenericConstructor(gpa, writer, map, parent_interface_entry.type_name, fn_name),
        else => continue,
    } else self.writeNormal(gpa, writer, map, parent_interface_entry.type_name, fn_name);

    try self.writeSerialize(gpa, writer, map, parent_interface_entry.type_name);
}

fn writeNormal(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    parent_interface: []const u8,
    fn_name: []const u8,
) !void {
    const fd_count = count: {
        var count: usize = 0;
        for (self.args.items) |arg| {
            if (arg.type == .fd) count += 1;
        }
        break :count count;
    };

    try writer.print("\tpub fn {s}(\n", .{fn_name});
    try writer.print("\t\tself: {s},\n", .{parent_interface});
    try writer.writeAll("\t\tconnection: *Connection,\n");
    for (self.args.items) |arg| try arg.write(gpa, writer, map);
    try writer.writeAll("\t) !void {\n");
    try writer.print(
        "\t\tvar message_buffer: [{s}_request_length]u8 = undefined;\n",
        .{self.name},
    );
    const serialize_fn_name = try util.snakeToPascal(gpa, self.name);
    defer gpa.free(serialize_fn_name);
    try writer.print("\t\tconst serialized_len = self.serialize{s}(\n", .{serialize_fn_name});
    try writer.writeAll("\t\t\t&message_buffer,\n");
    for (self.args.items) |arg| if (arg.type != .fd) try writer.print("\t\t\t{s}_,\n", .{arg.name});
    try writer.writeAll("\t\t);\n");
    if (fd_count > 0) {
        try writer.writeAll("\t\ttry connection.sendMessageWithFds(message_buffer[0..serialized_len], &.{\n");
        for (self.args.items) |arg| {
            if (arg.type == .fd) try writer.print("\t\t\t{s}_,\n", .{arg.name});
        }
        try writer.writeAll("\t\t});\n");
    } else {
        try writer.writeAll("\t\ttry connection.sendMessage(message_buffer[0..serialized_len]);\n");
    }
    try writer.writeAll("\t}\n\n");
}

fn writeConstructor(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    parent_interface: []const u8,
    fn_name: []const u8,
) !void {
    const fd_count = count: {
        var count: usize = 0;
        for (self.args.items) |arg| {
            if (arg.type == .fd) count += 1;
        }
        break :count count;
    };

    const return_arg = for (self.args.items) |arg| {
        if (arg.type == .new_id) break arg;
    } else unreachable;
    const entry = try map.get(return_arg.type.new_id);

    try writer.print("\n\tpub fn {s}(\n", .{fn_name});
    try writer.print("\t\tself: {s},\n", .{parent_interface});
    try writer.writeAll("\t\tconnection: *Connection,\n");
    for (self.args.items) |arg| if (arg.type != .new_id) try arg.write(gpa, writer, map);

    try writer.print("\t) !{s}.{s} {{\n", .{ entry.protocol, entry.type_name });

    try writer.print("\t\tconst {s}_ = try connection.ida.alloc();\n", .{return_arg.name});
    try writer.print(
        "\t\tvar message_buffer: [{s}_request_length]u8 = undefined;\n",
        .{self.name},
    );
    try writer.print(
        "\t\tconst serialized_len = self.serialize{c}{s}(\n",
        .{ std.ascii.toUpper(fn_name[0]), fn_name[1..] },
    );
    try writer.writeAll("\t\t\t&message_buffer,\n");
    for (self.args.items) |arg| if (arg.type != .fd) try writer.print("\t\t\t{s}_,\n", .{arg.name});
    try writer.writeAll("\t\t);\n");
    if (fd_count > 0) {
        try writer.writeAll("\t\ttry connection.sendMessageWithFds(message_buffer[0..serialized_len], &.{\n");
        for (self.args.items) |arg| {
            if (arg.type == .fd) try writer.print("\t\t\t{s}_,\n", .{arg.name});
        }
        try writer.writeAll("\t\t});\n");
    } else {
        try writer.writeAll("\t\ttry connection.sendMessage(message_buffer[0..serialized_len]);\n");
    }
    try writer.print("\t\treturn @enumFromInt({s}_);\n", .{return_arg.name});
    try writer.writeAll("\t}\n\n");
}

fn writeGenericConstructor(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    parent_interface: []const u8,
    fn_name: []const u8,
) !void {
    const fd_count = count: {
        var count: usize = 0;
        for (self.args.items) |arg| {
            if (arg.type == .fd) count += 1;
        }
        break :count count;
    };
    try writer.print("\n\tpub fn {s}(\n", .{fn_name});
    try writer.print("\t\tself: {s},\n", .{parent_interface});
    try writer.writeAll("\t\tconnection: *Connection,\n");
    try writer.writeAll("\t\tcomptime T: type,\n");
    try writer.writeAll("\t\tversion: T.Version,\n");
    for (self.args.items) |arg| if (arg.type != .any_new_id)
        try arg.write(gpa, writer, map);
    try writer.writeAll("\t) !T {\n");
    try writer.writeAll("\t\tconst new_id = try connection.ida.alloc();\n");
    try writer.print(
        "\t\tvar message_buffer: [{s}_request_length]u8 = undefined;\n",
        .{self.name},
    );
    try writer.print(
        "\t\tconst serialized_len = self.serialize{c}{s}(\n",
        .{ std.ascii.toUpper(fn_name[0]), fn_name[1..] },
    );
    try writer.writeAll("\t\t\t&message_buffer,\n");
    for (self.args.items) |arg| switch (arg.type) {
        .fd => {},
        .any_new_id => try writer.writeAll("\t\t\t.init(T, version, new_id),\n"),
        else => try writer.print("\t\t\t{s}_,\n", .{arg.name}),
    };
    try writer.writeAll("\t\t);\n");
    if (fd_count > 0) {
        try writer.writeAll("\t\ttry connection.sendMessageWithFds(message_buffer[0..serialized_len], &.{\n");
        for (self.args.items) |arg| {
            if (arg.type == .fd) try writer.print("\t\t\t{s}_,\n", .{arg.name});
        }
        try writer.writeAll("\t\t});\n");
    } else {
        try writer.writeAll("\t\ttry connection.sendMessage(message_buffer[0..serialized_len]);\n");
    }
    try writer.writeAll("\t\treturn @enumFromInt(new_id);\n");
    try writer.writeAll("\t}\n\n");
}

fn writeSerialize(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    interface_type: []const u8,
) !void {
    const fn_name = try util.snakeToPascal(gpa, self.name);
    defer gpa.free(fn_name);
    try writer.print("\tfn serialize{s}(\n", .{fn_name});
    try writer.print("\t\tself: {s},\n", .{interface_type});
    try writer.writeAll("\t\tbuf: []u8,\n");
    for (self.args.items) |arg| if (arg.type != .fd) try arg.write(gpa, writer, map);
    try writer.writeAll("\t) usize {\n");
    try writer.writeAll("\t\treturn wire.serializeArgs(\n");
    try writer.writeAll("\t\t\tbuf,\n");
    try writer.writeAll("\t\t\tself.getId(),\n");
    try writer.print("\t\t\t{s}_request_opcode,\n", .{self.name});
    if (self.args.items.len > 0) {
        try writer.writeAll("\t\t\t.{\n");
        for (self.args.items) |arg| switch (arg.type) {
            .fd => {},
            .string => try writer.print("\t\t\t\tcore.wire.String.init({s}_),\n", .{arg.name}),
            .optional_string => try writer.print("\t\t\t\tcore.wire.String.initNullable({s}_),\n", .{arg.name}),
            .array => try writer.print("\t\t\t\tcore.wire.Array.init({s}_),\n", .{arg.name}),
            .optional_object => try writer.print("\t\t\t\t@as(?u32, if ({s}_) |_inner| _inner.getId() else null),\n", .{arg.name}),
            .object => try writer.print("\t\t\t\t{s}_.getId(),\n", .{arg.name}),
            else => try writer.print("\t\t\t\t{s}_,\n", .{arg.name}),
        };
        try writer.writeAll("\t\t\t},\n");
    } else try writer.writeAll("\t\t\t.{},\n");
    try writer.writeAll("\t\t);\n");
    try writer.writeAll("\t}\n\n");
}

fn calculateMaxLength(self: *const Request) usize {
    var length: usize = 8; // Start at size of message header

    for (self.args.items) |arg| switch (arg.type) {
        // Strings and arrays have an undefined size,
        // so we can only assume the maximum capacity, as asserted by libwayland
        .array, .string, .optional_string, .any_new_id => return 4096,
        // Fds are not serialized on the wire, but sent via ancillary
        .fd => {},
        // Everything else is serialized as a 32 bit integer
        else => length += 4,
    };

    return length;
}

fn fnName(self: *const Request, gpa: Allocator) ![]const u8 {
    // Request name is a zig idenitfier, such as `error` or `type` and needs to be wrapped with @"..."
    if (!std.zig.isValidId(self.name))
        return self.fnNameInvalid(gpa);

    return util.snakeToCamel(gpa, self.name);
}

fn fnNameInvalid(self: *const Request, gpa: Allocator) ![]const u8 {
    var output = try std.ArrayList(u8).initCapacity(gpa, self.name.len + 3);
    output.appendSliceAssumeCapacity("@\"");
    var it = std.mem.tokenizeScalar(u8, self.name, '_');
    const first_tok = it.next().?;
    output.appendSliceAssumeCapacity(first_tok);
    while (it.next()) |tok| {
        output.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        if (tok.len > 1) output.appendSliceAssumeCapacity(tok[1..]);
    }
    output.appendAssumeCapacity('"');
    return try output.toOwnedSlice(gpa);
}

const std = @import("std");
const xml = @import("xml");
const util = @import("util.zig");
const Description = @import("Description.zig");
const Arg = @import("Arg.zig");
const InterfaceMap = @import("InterfaceMap.zig");
const Allocator = std.mem.Allocator;
