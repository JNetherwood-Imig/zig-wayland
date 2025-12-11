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
    const is_constructor = for (self.args.items) |arg| switch (arg.type) {
        .new_id, .any_new_id => break true,
        else => continue,
    } else false;

    const parent_interface_entry = try map.get(interface);

    const fn_name = try self.fnName(gpa);
    defer gpa.free(fn_name);

    const max_length = self.calculateMaxLength();
    try writer.print("\t\tpub const {s}_request_opcode = {d};\n", .{ self.name, opcode });
    try writer.print("\t\tpub const {s}_request_length = {d};\n", .{ self.name, max_length });

    if (is_constructor)
        try self.writeConstructor()
    else
        try self.writeNormal(writer, map, parent_interface_entry.type_name, fn_name);
}

fn writeNormal(
    self: *const Request,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
    parent_interface: []const u8,
    fn_name: []const u8,
) !void {
    try writer.print("\t\tpub fn {s}(\n", .{fn_name});
    try writer.print("\t\t\tself: {s},\n", .{parent_interface});
    try writer.writeAll("\t\t\tconnection: *Connection,\n");
    for (self.args.items) |arg| try arg.write(writer, map);
    try writer.print("\t\t) !{s} {{\n", .{"void"});
    try writer.writeAll("\t\t\t_ = connection;\n");
    for (self.args.items) |arg| try writer.print("\t\t\t_ = {s};\n", .{arg.name});
    try writer.print(
        "\t\t\tvar message_buffer: [{s}_request_length]u8 = undefined;\n",
        .{self.name},
    );
    try writer.print(
        "\t\t\ttry self.serialize{c}{s}(&message_buffer);\n",
        .{ std.ascii.toUpper(fn_name[0]), fn_name[1..] },
    );
    try writer.writeAll("\t\t}\n");
}

fn writeConstructor(self: *const Request) !void {
    _ = self;
}

fn writeSerialize(
    self: *const Request,
    gpa: Allocator,
    writer: *std.Io.Writer,
    interface_map: *const InterfaceMap,
    interface_type: []const u8,
    fn_name: []const u8,
) !void {
    _ = gpa;
    _ = interface_map;
    try writer.print(
        "\t\tpub fn serialize{c}{s}(\n",
        .{ std.ascii.toUpper(fn_name[0]), fn_name[1..] },
    );
    try writer.print("\t\t\tself: {s},\n", .{interface_type});
    try writer.writeAll("\t\t\tbuffer: []u8,\n");
    try writer.print("\t\t) !{s} {{\n", .{"void"});
    try writer.writeAll("\t\t\twire.serializeArgs(\n");
    try writer.writeAll("\t\t\t\tbuffer,");
    try writer.writeAll("\t\t\t\tself.id(),\n");
    try writer.print("\t\t\t\t{s}_request_opcode,\n", .{self.name});
    try writer.writeAll("\t\t}\n");
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

    var output = try std.ArrayList(u8).initCapacity(gpa, self.name.len);
    var it = std.mem.tokenizeScalar(u8, self.name, '_');

    // Since functions are camelCase, append the fist token without making it upper case
    const first_tok = it.next().?;
    output.appendSliceAssumeCapacity(first_tok);

    while (it.next()) |tok| {
        output.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        if (tok.len > 1) output.appendSliceAssumeCapacity(tok[1..]);
    }
    return try output.toOwnedSlice(gpa);
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
const Description = @import("Description.zig");
const Arg = @import("Arg.zig");
const InterfaceMap = @import("InterfaceMap.zig");
const Allocator = std.mem.Allocator;
