const Protocol = @This();

prefix: []const u8,
name: []const u8,
description: ?Description = null,
copyright: ?[]const u8 = null,
interfaces: std.ArrayList(Interface),

pub fn parse(gpa: Allocator, reader: *xml.Reader, prefix: []const u8) !Protocol {
    const name = for (0..reader.attributeCount()) |i| {
        const attrib = reader.attributeName(i);
        if (!std.mem.eql(u8, attrib, "name")) continue;
        break try reader.attributeValueAlloc(gpa, i);
    } else return error.NameNotFound;
    errdefer gpa.free(name);

    var description: ?Description = null;
    errdefer if (description) |*desc| desc.deinit(gpa);

    var copyright: ?[]const u8 = null;
    errdefer if (copyright) |c| gpa.free(c);

    var interfaces = try std.ArrayList(Interface).initCapacity(gpa, 4);
    errdefer interfaces.deinit(gpa);

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "protocol"))
                return error.UnexpectedElementEnd;
            break;
        },
        .element_start => {
            const elem = reader.elementName();
            if (std.mem.eql(u8, elem, "copyright"))
                copyright = try parseCopyright(gpa, reader)
            else if (std.mem.eql(u8, elem, "description"))
                description = try Description.parse(gpa, reader)
            else if (std.mem.eql(u8, elem, "interface")) {
                var interface = try Interface.parse(gpa, reader);
                errdefer interface.deinit(gpa);
                try interfaces.append(gpa, interface);
            } else return error.UnexpectedElement;
        },
        else => continue,
    } else |err| return err;

    return .{
        .prefix = try gpa.dupe(u8, prefix),
        .name = name,
        .description = description,
        .copyright = copyright,
        .interfaces = interfaces,
    };
}

pub fn deinit(self: *Protocol, gpa: Allocator) void {
    if (self.description) |*d| d.deinit(gpa);
    if (self.copyright) |c| gpa.free(c);
    for (self.interfaces.items) |*i| i.deinit(gpa);
    self.interfaces.deinit(gpa);
    gpa.free(self.prefix);
    gpa.free(self.name);
}

pub fn write(
    self: *const Protocol,
    gpa: Allocator,
    writer: *std.Io.Writer,
    map: *const InterfaceMap,
) !void {
    if (self.copyright) |c| try writeCopyright(c, writer);
    if (self.description) |d| try d.write(writer, "/// ");
    try writer.print("pub const {s} = struct {{\n", .{self.name});

    for (self.interfaces.items) |interface|
        try interface.write(gpa, writer, map);

    try writer.writeAll("};\n");
}

fn parseCopyright(gpa: Allocator, reader: *xml.Reader) ![]const u8 {
    var body = try std.ArrayList(u8).initCapacity(gpa, 1024);
    defer body.deinit(gpa);

    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const name = reader.elementName();
            if (!std.mem.eql(u8, name, "copyright"))
                return error.UnexpectedElementEnd;
            break;
        },
        .text => try body.appendSlice(gpa, reader.textRaw()),
        else => continue,
    } else |err| return err;

    return body.toOwnedSlice(gpa);
}

fn writeCopyright(copyright: []const u8, writer: *std.Io.Writer) !void {
    var it = std.mem.tokenizeScalar(u8, copyright, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t");
        if (line.len > 0) try writer.print("// {s}\n", .{line});
    }
}

const std = @import("std");
const xml = @import("xml");
const Description = @import("Description.zig");
const Interface = @import("Interface.zig");
const InterfaceMap = @import("InterfaceMap.zig");
const Allocator = std.mem.Allocator;
