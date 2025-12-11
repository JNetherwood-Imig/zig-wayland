const Arg = @This();

name: []const u8,
type: Type,
summary: ?[]const u8,
description: ?Description,

const Type = union(enum) {
    int: void,
    uint: void,
    fixed: void,
    string: void,
    optional_string: void,
    array: void,
    fd: void,
    object: []const u8,
    optional_object: []const u8,
    any_object: void,
    any_optional_object: void,
    any_new_id: void,
    @"enum": []const u8,
    new_id: []const u8,

    fn resolve(str: []const u8, allow_null: bool, interface: ?[]const u8, en: ?[]const u8) !Type {
        if (std.mem.eql(u8, str, "fixed"))
            return .fixed
        else if (std.mem.eql(u8, str, "string"))
            return if (allow_null) .optional_string else .string
        else if (std.mem.eql(u8, str, "array"))
            return .array
        else if (std.mem.eql(u8, str, "fd"))
            return .fd
        else if (std.mem.eql(u8, str, "int"))
            return if (en) |e| .{ .@"enum" = e } else .int
        else if (std.mem.eql(u8, str, "uint"))
            return if (en) |e| .{ .@"enum" = e } else .uint
        else if (std.mem.eql(u8, str, "new_id"))
            return if (interface) |i| .{ .new_id = i } else .any_new_id
        else if (std.mem.eql(u8, str, "object"))
            if (interface) |i|
                return if (allow_null) .{ .optional_object = i } else .{ .object = i }
            else
                return if (allow_null) .any_optional_object else .any_object
        else
            return error.UnknownArgType;
    }
};

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Arg {
    var name: ?[]const u8 = null;
    errdefer if (name) |n| gpa.free(n);
    var summary: ?[]const u8 = null;
    errdefer if (summary) |sum| gpa.free(sum);

    var type_str: ?[]const u8 = null;
    defer if (type_str) |t| gpa.free(t);

    var allow_null: bool = false;
    var interface: ?[]const u8 = null;
    errdefer if (interface) |i| gpa.free(i);
    var en: ?[]const u8 = null;
    errdefer if (en) |e| gpa.free(e);

    for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (std.mem.eql(u8, attrib, "name"))
            name = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "type"))
            type_str = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "summary"))
            summary = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "interface"))
            interface = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "allow-null"))
            allow_null = std.mem.eql(u8, reader.attributeValueRaw(i), "true")
        else if (std.mem.eql(u8, attrib, "enum"))
            en = try reader.attributeValueAlloc(gpa, i)
        else
            return error.UnexpectedArgAttribute;
    }

    var description: ?Description = null;

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "arg"))
                return error.UnexpectedElementEnd;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "description"))
                return error.UnexpectedArgElement;
            description = try Description.parse(gpa, reader);
        },
        else => continue,
    } else |err| return err;

    return .{
        .name = name orelse return error.NameNotFound,
        .summary = summary,
        .description = description,
        .type = try .resolve(type_str orelse return error.TypeNotFound, allow_null, interface, en),
    };
}

pub fn deinit(self: *Arg, gpa: Allocator) void {
    gpa.free(self.name);
    if (self.summary) |sum| gpa.free(sum);
    if (self.description) |*desc| desc.deinit(gpa);

    switch (self.type) {
        inline .@"enum", .object, .optional_object, .new_id => |str| gpa.free(str),
        else => {},
    }
}

pub fn write(self: *const Arg, gpa: Allocator, writer: *std.Io.Writer, map: *const InterfaceMap) !void {
    try writer.print("\t\t\t{s}: ", .{self.name});
    try self.writeTypeString(gpa, writer, map);
}

fn writeTypeString(
    self: *const Arg,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
) !void {
    if (self.type == .@"enum") {
        if (std.mem.indexOfScalar(u8, self.type.@"enum", '.')) |idx| {
            const interface = self.type.@"enum"[0..idx];
            const entry = try map.get(interface);
            const name = self.type.@"enum"[idx + 1 ..];
            const type_name = try util.snakeToPascal(gpa, name);
            defer gpa.free(type_name);
            try writer.print("{s}.{s}.{s}", .{ entry.protocol, entry.type_name, type_name });
        } else {
            const name = try util.snakeToPascal(gpa, self.type.@"enum");
            defer gpa.free(name);
            try writer.print("{s}", .{name});
        }
    } else if (self.type == .object) {
        const entry = try map.get(self.type.object);
        try writer.print("{s}.{s}", .{ entry.protocol, entry.type_name });
    } else if (self.type == .optional_object) {
        const entry = try map.get(self.type.optional_object);
        try writer.print("?{s}.{s}", .{ entry.protocol, entry.type_name });
    } else {
        const simple_type = switch (self.type) {
            .int => "i32",
            .uint => "u32",
            .fixed => "Fixed",
            .any_object => "u32",
            .any_optional_object => "?u32",
            .array => "[]const u8",
            .string => "[:0]const u8",
            .optional_string => "?[:0]const u8",
            .fd => "i32", // FIXME: should this be std.posix.fd_t?
            .new_id => "u32",
            .any_new_id => "core.wire.GenericNewId",
            else => unreachable,
        };
        try writer.writeAll(simple_type);
    }
    try writer.writeAll(",\n");
}

const std = @import("std");
const xml = @import("xml");
const util = @import("util.zig");
const InterfaceMap = @import("InterfaceMap.zig");
const Description = @import("Description.zig");
const Allocator = std.mem.Allocator;
