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

pub fn writeClient(self: *const Context, gpa: Allocator, writer: *std.Io.Writer) !void {
    for (self.protocols.items) |protocol|
        try protocol.write(gpa, writer, &self.interface_map);

    try self.writeEventUnion(gpa, writer);

    try writer.writeAll("const core = @import(\"core\");\n");
    try writer.writeAll("const wire = core.wire;\n");
    try writer.writeAll("const Fixed = core.Fixed;\n");
    try writer.writeAll("const Connection = core.Connection;\n");
    try writer.writeAll("const IdAllocator = core.IdAllocator;\n");
    try writer.writeAll("test {\n\t@import(\"std\").testing.refAllDeclsRecursive(@This());\n}\n");
}

pub fn writeServer(self: *const Context, gpa: Allocator, writer: *std.Io.Writer) !void {
    _ = self;
    _ = gpa;
    _ = writer;
}

const std = @import("std");
const xml = @import("xml");
const util = @import("Context/util.zig");
const Protocol = @import("Context/Protocol.zig");
const InterfaceMap = @import("Context/InterfaceMap.zig");
const Allocator = std.mem.Allocator;

fn writeEventUnion(self: *const Context, gpa: Allocator, writer: *std.Io.Writer) !void {
    try writer.writeAll("pub const Event = union(enum) {\n");
    for (self.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            if (interface.events.items.len == 0) continue;
            try writer.print("\t{s}: union(enum) {{\n", .{interface.name});
            for (interface.events.items) |event| {
                const map_entry = try self.interface_map.get(interface.name);
                const type_name = try util.snakeToPascal(gpa, event.name);
                defer gpa.free(type_name);
                const is_invalid = !std.zig.isValidId(event.name);
                try writer.print(
                    "\t\t{s}{s}{s}: {s}.{s}.{s}Event,\n",
                    .{
                        if (is_invalid) "@\"" else "",
                        event.name,
                        if (is_invalid) "\"" else "",
                        protocol.name,
                        map_entry.type_name,
                        type_name,
                    },
                );
            }
            try writer.writeAll("\t},\n");
        }
    }
    try writer.writeAll("};\n");
}
