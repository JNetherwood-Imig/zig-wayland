const Description = @This();

summary: []const u8,
body: ?[]const u8,

pub fn parse(gpa: Allocator, reader: *xml.Reader) !Description {
    const summary = for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (!std.mem.eql(u8, attrib, "summary")) continue;
        break try reader.attributeValueAlloc(gpa, i);
    } else return error.SummaryNotFound;
    errdefer gpa.free(summary);

    var body = try std.ArrayList(u8).initCapacity(gpa, 1024);
    defer body.deinit(gpa);

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const name = reader.elementName();
            if (!std.mem.eql(u8, name, "description"))
                return error.UnexpectedElementEnd;
            break;
        },
        .text => try body.appendSlice(gpa, reader.textRaw()),
        else => continue,
    } else |err| return err;

    const maybe_body = if (body.items.len > 0) try body.toOwnedSlice(gpa) else null;
    return .{ .summary = summary, .body = maybe_body };
}

pub fn deinit(self: *Description, gpa: Allocator) void {
    gpa.free(self.summary);
    if (self.body) |body| gpa.free(body);
}

const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
