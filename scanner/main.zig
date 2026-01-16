const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
const Protocol = @import("Protocol.zig");
const InterfaceMap = @import("InterfaceMap.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var io_impl: std.Io.Threaded = .init_single_threaded;
    const io = io_impl.io();

    var args = init.args.iterate();
    _ = args.skip();

    const mode = mode: {
        const mode_str = args.next() orelse return error.InvalidArgs;
        break :mode std.meta.stringToEnum(Mode, mode_str) orelse return error.InvalidMode;
    };

    const input_path = args.next() orelse return error.InvalidArgs;
    const input_file = try std.Io.Dir.cwd().openFile(io, input_path, .{});
    defer input_file.close(io);

    var prefix: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var imports: std.ArrayList([]const u8) = try .initCapacity(gpa, 8);
    defer imports.deinit(gpa);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-p")) {
            prefix = args.next() orelse return error.ExpectedPrefix;
        } else if (std.mem.eql(u8, arg, "-o")) {
            output_path = args.next() orelse return error.ExpectedOutputPath;
        } else if (std.mem.eql(u8, arg, "-i")) {
            try imports.append(gpa, args.next() orelse return error.ExpectedImportPath);
        } else return error.UnexpectedArgument;
    }

    var input_buffer: [4096]u8 = undefined;
    var input_reader = input_file.reader(io, &input_buffer);
    const io_reader = &input_reader.interface;

    var stream_reader = xml.Reader.Streaming.init(gpa, io_reader, .{});
    defer stream_reader.deinit();

    var protocol = try parseDocument(gpa, &stream_reader.interface, prefix orelse "");
    defer protocol.deinit(gpa);

    var map: InterfaceMap = .empty;
    defer map.deinit(gpa);

    for (protocol.interfaces.items) |iface| {
        try map.put(gpa, &protocol, &iface);
    }

    try addImportsToMap(io, gpa, &map, imports.items);

    const file_ext = if (mode == .dep_info) "dep" else "zig";
    var output_file_buf: [1024]u8 = undefined;
    output_path = output_path orelse try std.fmt.bufPrint(&output_file_buf, "{s}.{s}", .{ protocol.name, file_ext });
    const output_file = try std.Io.Dir.cwd().createFile(io, output_path.?, .{});
    defer output_file.close(io);

    var output_buffer: [4096]u8 = undefined;
    var file_writer = output_file.writer(io, &output_buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};

    switch (mode) {
        .client => try protocol.emitClientCode(gpa, writer, &map, imports.items),
        .server => try protocol.emitServerCode(gpa, writer, &map, imports.items),
        .dep_info => try protocol.emitDepInfo(writer, &map),
    }
}

fn parseDocument(gpa: Allocator, reader: *xml.Reader, prefix: []const u8) !Protocol {
    while (reader.read()) |node| switch (node) {
        .element_start => {
            if (!std.mem.eql(u8, reader.elementName(), "protocol"))
                continue;
            return try Protocol.parse(gpa, reader, prefix);
        },
        else => continue,
    } else |err| return err;
    return error.UnexpectedEof;
}

fn addImportsToMap(io: std.Io, gpa: Allocator, map: *InterfaceMap, imports: []const []const u8) !void {
    for (imports) |path| {
        const import_file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer import_file.close(io);
        var import_buf: [4096]u8 = undefined;
        var import_reader = import_file.reader(io, &import_buf);
        const import_content = try import_reader.interface.allocRemaining(gpa, .unlimited);
        defer gpa.free(import_content);
        var line_it = std.mem.tokenizeScalar(u8, import_content, '\n');
        while (line_it.next()) |line| {
            const interface_idx = std.mem.indexOfScalar(u8, line, ' ').?;
            const protocol_idx = std.mem.indexOfScalar(u8, line[interface_idx + 1 ..], ' ').?;

            const interface = line[0..interface_idx];
            const protocol = line[interface_idx + 1 ..][0..protocol_idx];
            const type_name = line[interface_idx + protocol_idx + 2 ..];
            try map.putRaw(gpa, interface, protocol, type_name);
        }
    }
}

const Mode = enum {
    client,
    server,
    dep_info,
};
