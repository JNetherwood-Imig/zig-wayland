const Event = @This();

name: []const u8,
type: enum { none, destructor } = .none,
since: u32,
deprecated_since: ?u32,
description: ?Description,
args: std.ArrayList(Arg),

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Event {
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
            if (!std.mem.eql(u8, elem, "event"))
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

pub fn deinit(self: *Event, gpa: Allocator) void {
    gpa.free(self.name);
    if (self.description) |*desc| desc.deinit(gpa);
    for (self.args.items) |*arg| arg.deinit(gpa);
    self.args.deinit(gpa);
}

const std = @import("std");
const xml = @import("xml");
const Description = @import("Description.zig");
const Arg = @import("Arg.zig");
const Allocator = std.mem.Allocator;
