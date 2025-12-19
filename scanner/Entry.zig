const Entry = @This();

name: []const u8,
value: i32,
summary: ?[]const u8,
since: u32,
deprecated_since: ?u32,
description: ?Description,

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Entry {
    var name: ?[]const u8 = null;
    errdefer if (name) |n| gpa.free(n);
    var summary: ?[]const u8 = null;
    errdefer if (summary) |s| gpa.free(s);

    var value: ?i32 = null;
    var since: ?u32 = null;
    var deprecated_since: ?u32 = null;

    for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (std.mem.eql(u8, attrib, "name"))
            name = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "summary"))
            summary = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "since"))
            since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else if (std.mem.eql(u8, attrib, "deprecated-since"))
            deprecated_since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else if (std.mem.eql(u8, attrib, "value")) {
            const raw_value = reader.attributeValueRaw(i);
            value = if (std.mem.startsWith(u8, raw_value, "0x"))
                try std.fmt.parseInt(i32, raw_value[2..], 16)
            else
                try std.fmt.parseInt(i32, raw_value, 10);
        } else return error.UnexpectedAttribute;
    }

    var description: ?Description = null;

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "entry"))
                return error.UnexpectedElement;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "description"))
                return error.UnexpectedElement;
            description = try Description.parse(gpa, reader);
        },
        else => continue,
    } else |err| return err;

    return .{
        .name = name orelse return error.NameNotFound,
        .value = value orelse return error.ValueNotFound,
        .since = since orelse 1,
        .deprecated_since = deprecated_since,
        .summary = summary,
        .description = description,
    };
}

pub fn deinit(self: *Entry, gpa: Allocator) void {
    if (self.description) |*desc| desc.deinit(gpa);
    if (self.summary) |s| gpa.free(s);
    gpa.free(self.name);
}

const std = @import("std");
const xml = @import("xml");
const Description = @import("Description.zig");
const Allocator = std.mem.Allocator;
