const std = @import("std");
const xml = @import("xml");
const Context = @import("Context.zig");

const Mode = enum {
    client,
    server,
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var context = try Context.init(gpa);
    defer context.deinit(gpa);

    var mode = Mode.client; // Default to generating client code, since that's most likely
    var output_path: ?[]const u8 = null;
    var current_prefix: []const u8 = "";

    var args = std.process.args();
    _ = args.skip(); // skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-m")) {
            // Argument codegen mode and must be either "client" or "server"
            const mode_str = args.next() orelse return error.ExpectedMode;
            mode = std.meta.stringToEnum(Mode, mode_str) orelse
                return error.InvalidMode;
        } else if (std.mem.eql(u8, arg, "-o")) {
            // Argument specifies output file
            output_path = args.next() orelse return error.ExpectedOutputPath;
        } else if (std.mem.eql(u8, arg, "-p")) {
            // Argument specifies the prefix to strip from the front of all
            // interfaces parsed from the next protocol input file
            current_prefix = args.next() orelse return error.ExpectedPrefix;
        } else {
            // Argument is an input file path (protocol xml)
            const path = arg;
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            // Set up Io.Reader for input file
            var input_buffer: [4096]u8 = undefined;
            var input_reader = file.reader(&input_buffer);
            const io_reader = &input_reader.interface;

            // Get xml.Reader for document parsing
            var stream_reader = xml.Reader.Streaming.init(gpa, io_reader, .{});
            defer stream_reader.deinit();
            const xml_reader = &stream_reader.interface;

            // Parse document and append to context
            try context.parseDocument(gpa, xml_reader, current_prefix);
        }
    }

    // Make a map of protocol-defined interface names to generated type names (i.e. wl_display -> wayland.Display)
    try context.genInterfaceMap(gpa);

    if (output_path) |path| {
        const output_file = try std.fs.cwd().createFile(path, .{});
        defer output_file.close();

        var output_buffer: [4096]u8 = undefined;
        var file_writer = output_file.writer(&output_buffer);
        const writer = &file_writer.interface;

        try switch (mode) {
            .client => context.writeClient(gpa, writer),
            .server => context.writeServer(gpa, writer),
        };
        try writer.flush();
    }
}
