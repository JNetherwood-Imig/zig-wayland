const std = @import("std");
const xml = @import("xml");
const util = @import("util.zig");
const InterfaceMap = @import("InterfaceMap.zig");
const Description = @import("Description.zig");
const Request = @import("Request.zig");
const Event = @import("Event.zig");
const Enum = @import("Enum.zig");
const log = std.log.scoped(.scanner);
const Allocator = std.mem.Allocator;

const Interface = @This();

name: []const u8,
version: u32,
description: ?Description = null,
requests: std.ArrayList(Request),
events: std.ArrayList(Event),
enums: std.ArrayList(Enum),

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Interface {
    var name: ?[]const u8 = null;
    errdefer if (name) |n| gpa.free(n);
    var version: ?u32 = null;

    for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (std.mem.eql(u8, attrib, "name"))
            name = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "version"))
            version = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else
            continue;
    }

    var description: ?Description = null;
    errdefer if (description) |*desc| desc.deinit(gpa);

    var requests = try std.ArrayList(Request).initCapacity(gpa, 8);
    errdefer {
        for (requests.items) |*req| req.deinit(gpa);
        requests.deinit(gpa);
    }

    var events = try std.ArrayList(Event).initCapacity(gpa, 8);
    errdefer {
        for (events.items) |*ev| ev.deinit(gpa);
        events.deinit(gpa);
    }

    var enums = try std.ArrayList(Enum).initCapacity(gpa, 4);
    errdefer {
        for (enums.items) |*en| en.deinit(gpa);
        enums.deinit(gpa);
    }

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "interface"))
                return error.UnexpectedElementEnd;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (std.mem.eql(u8, elem, "description")) {
                description = try Description.parse(gpa, reader);
            } else if (std.mem.eql(u8, elem, "request")) {
                var request = try Request.parse(gpa, reader);
                errdefer request.deinit(gpa);
                try requests.append(gpa, request);
            } else if (std.mem.eql(u8, elem, "event")) {
                var event = try Event.parse(gpa, reader);
                errdefer event.deinit(gpa);
                try events.append(gpa, event);
            } else if (std.mem.eql(u8, elem, "enum")) {
                var en = try Enum.parse(gpa, reader);
                errdefer en.deinit(gpa);
                try enums.append(gpa, en);
            } else return error.UnexpectedElement;
        },
        else => continue,
    } else |err| return err;

    return .{
        .name = name orelse return error.NameNotFound,
        .version = version orelse return error.VersionNotFound,
        .description = description,
        .requests = requests,
        .events = events,
        .enums = enums,
    };
}

pub fn deinit(self: *Interface, gpa: Allocator) void {
    gpa.free(self.name);
    if (self.description) |*desc| desc.deinit(gpa);
    for (self.requests.items) |*req| req.deinit(gpa);
    for (self.events.items) |*ev| ev.deinit(gpa);
    for (self.enums.items) |*en| en.deinit(gpa);
    self.requests.deinit(gpa);
    self.events.deinit(gpa);
    self.enums.deinit(gpa);
}

pub fn write(
    self: *const Interface,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
) !void {
    const map_entry = try map.get(self.name);
    const type_name = map_entry.type_name;

    if (self.description) |d| try d.write(writer, "/// ");
    try writer.print("pub const {s} = enum(u32) {{\n", .{type_name});
    try writer.writeAll("\tnull_handle = 0,\n\t_,\n\n");
    try writer.print("\tpub const interface = \"{s}\";\n\n", .{self.name});
    try writer.writeAll("\tpub const Version = enum(u32) {\n");
    for (0..self.version) |v| try writer.print("\t\tv{d} = {d},\n", .{ v + 1, v + 1 });
    try writer.writeAll("\t};\n\n");
    try writer.print(
        "\tpub fn getId(self: {s}) u32 {{\n\t\treturn @intFromEnum(self);\n\t}}\n",
        .{type_name},
    );

    for (self.requests.items, 0..) |request, opcode|
        try request.write(gpa, writer, map, self.name, opcode);

    for (self.events.items, 0..) |event, opcode|
        try event.write(gpa, writer, map, self.name, opcode);

    for (self.enums.items) |en|
        try en.write(gpa, writer);

    try writer.writeAll("};\n\n");
}

pub fn typeName(self: *const Interface, gpa: Allocator, prefix: []const u8) ![]const u8 {
    const stripped_name = name: {
        const name = if (std.mem.startsWith(u8, self.name, prefix))
            self.name[prefix.len..]
        else {
            log.err("Invalid prefix {s} for interface {s}.", .{ prefix, self.name });
            return error.InvalidPrefix;
        };

        if (std.mem.lastIndexOfScalar(u8, name, '_')) |idx| {
            if (name.len > idx + 2 and
                name[idx + 1] == 'v')
            {
                for (name[idx + 2 .. name.len]) |c| {
                    if (!std.ascii.isDigit(c)) break :name name;
                }
                break :name name[0..idx];
            }
        }
        break :name name;
    };

    return util.snakeToPascal(gpa, stripped_name);
}
