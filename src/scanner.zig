const std = @import("std");
const xml = @import("xml");
const log = std.log.scoped(.scanner);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var mode = Mode.client;
    var output_file: ?[]const u8 = null;
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
            output_file = args.next() orelse return error.ExpectedOutputFile;
        } else if (std.mem.eql(u8, arg, "-p")) {
            // Argument specifies the prefix to strip from the front of all
            // interfaces parsed from the next protocol input file
            current_prefix = args.next() orelse return error.ExpectedPrefix;
        } else {
            // Argument is an input file path (protocol xml)
            const path = arg;
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            var input_buffer: [4096]u8 = undefined;
            var input_reader = file.reader(&input_buffer);
            const io_reader = &input_reader.interface;

            var stream_reader = xml.Reader.Streaming.init(gpa, io_reader, .{});
            defer stream_reader.deinit();
            const xml_reader = &stream_reader.interface;

            try parseDoc(xml_reader);
        }
    }
}

fn parseDoc(reader: *xml.Reader) !void {
    while (reader.read()) |node| switch (node) {
        // eof,
        // xml_declaration,
        // element_start,
        // element_end,
        // comment,
        // pi,
        // text,
        // cdata,
        // character_reference,
        // entity_reference,
        .eof => return error.UnexpectedEof,
        .element_start => {
            const name = reader.elementName();
            try parseProtocol(reader, name);
        },
        .element_end => {},
        inline else => |n| log.debug("Got {t}.", .{n}),
    } else |err| switch (err) {
        error.MalformedXml => {
            const loc = reader.errorLocation();
            const code = reader.errorCode();
            log.err("{f}: {t}", .{ loc, code });
            return error.MalformedXml;
        },
        else => |e| return e,
    }
}

fn parseProtocol(reader: *xml.Reader, name: []const u8) !void {
    while (reader.read()) |node| switch (node) {
        .eof => return error.UnexpectedEof,
        .element_end => {
            const end_name = reader.elementName();
            if (std.mem.eql(u8, end_name, name)) {
                // TODO
                return;
            } else return error.UnexpectedElementEnd;
        },
        else => continue,
    } else |err| return err;
}

const Mode = enum {
    client,
    server,
};
