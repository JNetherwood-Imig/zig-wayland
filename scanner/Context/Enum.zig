const Enum = @This();

name: []const u8,
since: u32,
type: enum { none, bitfield } = .none,
description: ?Description = null,
entries: std.ArrayList(Entry),

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Enum {
    var name: ?[]const u8 = null;
    var since: ?u32 = null;
    var is_bitfield = false;

    for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (std.mem.eql(u8, attrib, "name"))
            name = try reader.attributeValueAlloc(gpa, i)
        else if (std.mem.eql(u8, attrib, "since"))
            since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
        else if (std.mem.eql(u8, attrib, "bitfield"))
            is_bitfield = std.mem.eql(u8, reader.attributeValueRaw(i), "true")
        else
            return error.UnexpectedAttribute;
    }

    var entries = try std.ArrayList(Entry).initCapacity(gpa, 8);
    errdefer {
        for (entries.items) |*ent| ent.deinit(gpa);
        entries.deinit(gpa);
    }

    var description: ?Description = null;

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "enum"))
                return error.UnexpectedElementEnd;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (std.mem.eql(u8, elem, "description"))
                description = try Description.parse(gpa, reader)
            else if (std.mem.eql(u8, elem, "entry")) {
                var entry = try Entry.parse(gpa, reader);
                errdefer entry.deinit(gpa);
                try entries.append(gpa, entry);
            } else return error.UnexpectedElement;
        },
        else => continue,
    } else |err| return err;

    return .{
        .name = name orelse return error.NameNotFound,
        .since = since orelse 1,
        .type = if (is_bitfield) .bitfield else .none,
        .description = description,
        .entries = entries,
    };
}

pub fn deinit(self: *Enum, gpa: Allocator) void {
    for (self.entries.items) |*entry| entry.deinit(gpa);
    self.entries.deinit(gpa);
    if (self.description) |*d| d.deinit(gpa);
    gpa.free(self.name);
}

const std = @import("std");
const xml = @import("xml");
const Description = @import("Description.zig");
const Entry = @import("Entry.zig");
const Allocator = std.mem.Allocator;
