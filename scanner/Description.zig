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

pub fn deinit(self: Description, gpa: Allocator) void {
    gpa.free(self.summary);
    if (self.body) |body| gpa.free(body);
}

pub fn write(self: *const Description, writer: *std.Io.Writer, prefix: []const u8) !void {
    if (self.body) |body| {
        var it = std.mem.tokenizeScalar(u8, body, '\n');
        while (it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t");
            if (line.len > 0) try writer.print("{s}{s}\n", .{ prefix, line });
        }
    } else try printSummary(self.summary, prefix, writer);
}

pub fn printSummary(summary: []const u8, prefix: []const u8, writer: *std.Io.Writer) !void {
    const trimmed = std.mem.trim(u8, summary, " \n\t");
    const needs_period = trimmed[trimmed.len - 1] != '.';
    try writer.print("{s}{c}{s}{s}\n", .{
        prefix,
        std.ascii.toUpper(trimmed[0]),
        trimmed[1..],
        if (needs_period) "." else "",
    });
}

const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
