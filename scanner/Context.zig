const Context = @This();

protocols: std.ArrayList(Protocol),
interface_map: InterfaceMap,

pub fn init(gpa: Allocator) !Context {
    return .{
        .protocols = try .initCapacity(gpa, 4),
        .interface_map = .empty,
    };
}

pub fn deinit(self: *Context, gpa: Allocator) void {
    for (self.protocols.items) |*protocol|
        protocol.deinit(gpa);
    self.protocols.deinit(gpa);
    self.interface_map.deinit(gpa);
}

pub fn parseDocument(
    self: *Context,
    gpa: Allocator,
    reader: *xml.Reader,
    prefix: []const u8,
) !void {
    while (reader.read()) |node| switch (node) {
        .eof => break,
        .element_start => {
            const elem = reader.elementName();
            if (!std.mem.eql(u8, elem, "protocol")) continue;
            var protocol = try Protocol.parse(gpa, reader, prefix);
            errdefer protocol.deinit(gpa);
            try self.protocols.append(gpa, protocol);
        },
        else => continue,
    } else |err| return err;
}

pub fn genInterfaceMap(self: *Context, gpa: Allocator) !void {
    for (self.protocols.items) |*p| {
        for (p.interfaces.items) |*i| {
            try self.interface_map.put(gpa, p, i);
        }
    }
}

pub fn write(self: *const Context, gpa: Allocator, writer: *std.Io.Writer) !void {
    try writer.writeAll("const core = @import(\"core\");\n");
    try writer.writeAll("const wire = core.wire;\n");
    try writer.writeAll("const Fixed = core.Fixed;\n");
    try writer.writeAll("const Connection = core.Connection;\n");
    try writer.writeAll("const IdAllocator = core.IdAllocator;\n");

    for (self.protocols.items) |protocol|
        try protocol.write(gpa, writer, &self.interface_map);
}

const std = @import("std");
const xml = @import("xml");
const Protocol = @import("Context/Protocol.zig");
const InterfaceMap = @import("Context/InterfaceMap.zig");
const Allocator = std.mem.Allocator;
