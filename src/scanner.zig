// TODO: multi-protocol generation
// TODO: interface map
// TODO: requests
// TODO: figure out event model
// TODO: versioned interface types

// usage: scanner (<input file>)+ -o <output file> -m <mode (client|server)>

const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var args = std.process.args();
    _ = args.skip();

    const mode = mode: {
        const mode_str = args.next() orelse return error.ExpectedMode;
        if (std.mem.eql(u8, mode_str, "client")) break :mode CodegenMode.client;
        if (std.mem.eql(u8, mode_str, "server")) break :mode CodegenMode.server;
        return error.InvalidMode;
    };

    var collect_path: ?[]const u8 = null;
    var prefix: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-c")) {
            collect_path = args.next() orelse return error.ExpectedCollectPath;
        } else if (std.mem.eql(u8, arg, "-p")) {
            prefix = args.next() orelse return error.ExpectedPrefix;
        } else {
            const input_path = args.next() orelse return error.ExpectedInputPath;
            const output_path = args.next() orelse return error.ExpectedOutputPath;
            try genProtocol(gpa, mode, input_path, output_path, prefix orelse "");
        }
    }
}

const Parser = struct {
    mode: Mode,
    output_path: []const u8,
    input_paths: std.ArrayList([]const u8),
    context: Context,

    const Mode = enum { client, server };

    const Context = struct {
        current_protocol: Protocol,
        current_interface: Interface,
    };

    const Protocol = struct {
        name: []const u8,
        summary: ?[]const u8,
        description: ?[]const u8,
        interfaces: ArrayList(Interface),
    };

    const Interface = struct {
        name: []const u8,
        type_name: []const u8,
        max_version: u32,
        summary: ?[]const u8,
        description: ?[]const u8,
    };

    const Request = struct {
        name: []const u8,
        fn_name: []const u8,
    };
};

fn genProtocol(
    gpa: Allocator,
    mode: CodegenMode,
    input: []const u8,
    output: []const u8,
    prefix: []const u8,
) !void {
    const input_file = try std.fs.cwd().openFile(input, .{});
    defer input_file.close();
    const output_file = try std.fs.cwd().createFile(output, .{});
    defer output_file.close();

    var input_reader = input_file.reader(&.{});
    const reader = &input_reader.interface;
    const contents = try reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(contents);

    var protocol = try xml.parse(xml.Document(RawProtocol), gpa, contents);
    defer protocol.deinit(gpa);
    var output_writer = output_file.writer(&.{});
    const writer = &output_writer.interface;

    switch (mode) {
        .client => try writeClientProtocol(
            gpa,
            writer,
            protocol.value,
            prefix,
        ),
        .server => try writeServerProtocol(
            gpa,
            writer,
            protocol.value,
            prefix,
        ),
    }
}

fn writeClientProtocol(
    gpa: Allocator,
    writer: *Writer,
    protocol: RawProtocol,
    prefix: []const u8,
) !void {
    if (protocol.copyright.value) |copyright|
        try writeCopyright(writer, copyright);
    if (protocol.description.value) |description| {
        try writeDescription(writer, description, "//!");
        try writer.writeAll("\n");
    }

    for (protocol.interfaces.value.items) |interface|
        try writeClientInterface(gpa, writer, interface, prefix);

    try writer.writeAll("const core = @import(\"core\");\n");
    try writer.writeAll("const client_core = @import(\"client_core\");\n");
}

fn writeClientInterface(
    gpa: Allocator,
    writer: *Writer,
    interface: RawInterface,
    prefix: []const u8,
) !void {
    const name = name: {
        const prefix_stripped = interface.name.value[prefix.len..];
        const version_stripped =
            if (std.mem.lastIndexOfScalar(u8, prefix_stripped, '_')) |i| blk: {
                if (prefix_stripped.len > i + 2 and
                    prefix_stripped[i + 1] == 'v' and
                    std.ascii.isDigit(prefix_stripped[i + 2]))
                    break :blk prefix_stripped[0..i];
                break :blk prefix_stripped;
            } else prefix_stripped;
        const pascal = try snakeToPascal(gpa, version_stripped);
        break :name pascal;
    };
    defer gpa.free(name);

    if (interface.description.value) |description|
        try writeDescription(writer, description, "///");

    try writer.print("pub const {s} = packed struct(u32) {{\n", .{name});
    try writer.print(
        "\tpub const interface = \"{s}\";\n",
        .{interface.name.value},
    );
    try writer.print(
        "\tpub const max_version = {s};\n",
        .{interface.version.value},
    );
    try writer.writeAll("\n\t_: u32 = 0,\n");
    try writer.print(
        "\n\tpub fn id(self: {s}) u32 {{\n\t\treturn @bitCast(self);\n\t}}\n",
        .{name},
    );
    try writer.print(
        "\n\tpub fn fromId(init_id: u32) {s} {{\n\t\treturn @bitCast(init_id);\n\t}}\n",
        .{name},
    );

    for (interface.requests.value.items) |req|
        try writeRequest(gpa, writer, req);

    for (interface.enums.value.items) |e|
        try writeEnum(gpa, writer, e);

    try writer.writeAll("};\n\n");
}

fn writeRequest(gpa: Allocator, writer: *Writer, request: RawRequest) !void {
    const name = try snakeToPascal(gpa, request.name.value);
    defer gpa.free(name);
    name[0] = std.ascii.toLower(name[0]);

    if (request.description.value) |desc|
        try writeDescription(writer, desc, "\t///");
    const is_invalid = !std.zig.isValidId(name);
    try writer.print("\tpub fn {s}{s}{s}(\n", .{
        if (is_invalid) "@\"" else "",
        name,
        if (is_invalid) "\"" else "",
    });
    try writer.writeAll("\t\tself: @This(),\n");
    try writer.writeAll("\t) void {\n");
    try writer.writeAll("\t\t_ = self;\n");
    try writer.writeAll("\t}\n");
}

fn writeCreateRequest(gpa: Allocator, writer: *Writer, request: RawRequest) !void {
    _ = gpa;
    _ = writer;
    _ = request;
}

fn writeGenericCreateRequest(
    gpa: Allocator,
    writer: *Writer,
    request: RawRequest,
) !void {
    _ = gpa;
    _ = writer;
    _ = request;
}

fn writeEnum(gpa: Allocator, writer: *Writer, e: RawEnum) !void {
    try writer.writeAll("\n");
    if (e.description.value) |description| {
        try writeDescription(writer, description, "\t///");
    }

    if (std.mem.eql(u8, e.bitfield.value orelse "false", "true"))
        return writeBitfield(gpa, writer, e);

    const name = try snakeToPascal(gpa, e.name.value);
    defer gpa.free(name);
    try writer.print("\tpub const {s} = enum(i32) {{\n", .{name});
    for (e.entries.value.items) |entry|
        try writeEnumEntry(writer, entry);
    try writer.writeAll("\t};\n");
}

fn writeEnumEntry(writer: *Writer, entry: RawEntry) !void {
    if (entry.deprecated_since.value) |deprecated_since| {
        try writer.print(
            "\t\t/// Deprecated since version {s}.",
            .{deprecated_since},
        );
    } else if (entry.description.value) |description| {
        try writeDescription(writer, description, "\t\t///");
    }

    const is_invalid = !std.zig.isValidId(entry.name.value);
    try writer.print(
        "\t\t{s}{s}{s} = {s},\n",
        .{
            if (is_invalid) "@\"" else "",
            entry.name.value,
            if (is_invalid) "\"" else "",
            entry.value.value,
        },
    );
}

fn writeBitfield(gpa: Allocator, writer: *Writer, e: RawEnum) !void {
    const needs_bitflags = for (e.entries.value.items) |entry| {
        const is_hex = std.mem.startsWith(u8, entry.value.value, "0x");
        const str = if (is_hex) entry.value.value[2..] else entry.value.value;
        const base: u8 = if (is_hex) 16 else 10;
        const value = try std.fmt.parseInt(u32, str, base);
        if (value != 0 and !std.math.isPowerOfTwo(value)) break true;
    } else false;
    if (needs_bitflags)
        return writeBitflags(gpa, writer, e);

    const name = try snakeToPascal(gpa, e.name.value);
    defer gpa.free(name);
    try writer.print("\tpub const {s} = packed struct(u32) {{\n", .{name});
    var current_bit: usize = 1;
    for (e.entries.value.items) |entry| {
        const is_hex = std.mem.startsWith(u8, entry.value.value, "0x");
        const str = if (is_hex) entry.value.value[2..] else entry.value.value;
        const base: u8 = if (is_hex) 16 else 10;
        const value = try std.fmt.parseInt(u32, str, base);
        if (value != 0) {
            const value_bit = std.math.log2(value) + 1;
            if (value_bit != current_bit) {
                for (0..value_bit - current_bit) |_| {
                    try writer.writeAll("\t\t/// Padding: DO NOT USE.\n");
                    try writer.print("\t\t__unused{d}: u1 = 0,\n", .{current_bit});
                    current_bit += 1;
                }
            }
            current_bit += 1;
        }
        try writeBitfieldEntry(writer, entry, value == 0);
    }
    try writer.writeAll("\t};\n");
}

fn writeBitfieldEntry(writer: *Writer, entry: RawEntry, is_zero: bool) !void {
    if (entry.deprecated_since.value) |deprecated_since|
        try writer.print(
            "\t\t/// Deprecated since version {s}.",
            .{deprecated_since},
        )
    else if (entry.description.value) |description|
        try writeDescription(writer, description, "\t\t///");

    const is_invalid = !std.zig.isValidId(entry.name.value);
    if (is_zero) {
        try writer.print(
            "\t\tpub const {s}{s}{s}: @This() = @bitCast(0);\n",
            .{
                if (is_invalid) "@\"" else "",
                entry.name.value,
                if (is_invalid) "\"" else "",
            },
        );
    } else {
        try writer.print(
            "\t\t{s}{s}{s}: bool = false,\n",
            .{
                if (is_invalid) "@\"" else "",
                entry.name.value,
                if (is_invalid) "\"" else "",
            },
        );
    }
}

fn writeBitflags(gpa: Allocator, writer: *Writer, e: RawEnum) !void {
    const name = try snakeToPascal(gpa, e.name.value);
    defer gpa.free(name);
    try writer.print("\tpub const {s} = struct {{\n", .{name});
    for (e.entries.value.items) |entry|
        try writeBitflagsEntry(writer, entry);
    try writer.writeAll("\t};\n");
}

fn writeBitflagsEntry(writer: *Writer, entry: RawEntry) !void {
    if (entry.deprecated_since.value) |deprecated_since| {
        try writer.print(
            "\t\t/// Deprecated since version {s}.",
            .{deprecated_since},
        );
    } else if (entry.description.value) |description| {
        try writeDescription(writer, description, "\t\t///");
    }

    const is_invalid = !std.zig.isValidId(entry.name.value);
    try writer.print(
        "\t\tpub const {s}{s}{s}: u32 = {s};\n",
        .{
            if (is_invalid) "@\"" else "",
            entry.name.value,
            if (is_invalid) "\"" else "",
            entry.value.value,
        },
    );
}

fn writeServerProtocol(
    gpa: Allocator,
    writer: *Writer,
    protocol: RawProtocol,
    prefix: []const u8,
) !void {
    _ = gpa;
    _ = writer;
    _ = protocol;
    _ = prefix;
}

fn writeCopyright(writer: *Writer, copyright: RawCopyright) !void {
    var it = std.mem.splitScalar(u8, copyright.body.data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (it.peek() != null)
            try writer.print("//! {s}\n", .{trimmed});
    }
    try writer.writeAll("\n");
}

fn writeDescription(
    writer: *Writer,
    description: RawDescription,
    comment_str: []const u8,
) !void {
    try writer.print(
        "{s} {s}\n{s}\n",
        .{ comment_str, description.summary.value, comment_str },
    );

    var it = std.mem.splitScalar(u8, description.body.data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (it.peek() != null)
            try writer.print("{s} {s}\n", .{ comment_str, trimmed });
    }
}

fn snakeToPascal(gpa: Allocator, snake: []const u8) ![]u8 {
    var pascal = try std.ArrayList(u8).initCapacity(gpa, snake.len);
    var it = std.mem.tokenizeScalar(u8, snake, '_');
    while (it.next()) |tok| {
        pascal.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        if (tok.len > 1) pascal.appendSliceAssumeCapacity(tok[1..]);
    }
    return pascal.toOwnedSlice(gpa);
}

const RawProtocol = struct {
    name: xml.Attribute("name"),
    copyright: xml.OptionalElement("copyright", RawCopyright),
    description: xml.OptionalElement("description", RawDescription),
    interfaces: xml.ElementList("interface", RawInterface),
};

const RawInterface = struct {
    name: xml.Attribute("name"),
    version: xml.Attribute("version"),
    description: xml.OptionalElement("description", RawDescription),
    requests: xml.ElementList("request", RawRequest),
    events: xml.ElementList("event", RawEvent),
    enums: xml.ElementList("enum", RawEnum),
};

const RawRequest = struct {
    name: xml.Attribute("name"),
    type: xml.OptionalAttribute("type"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", RawDescription),
    args: xml.ElementList("arg", RawArg),
};

const RawEvent = struct {
    name: xml.Attribute("name"),
    type: xml.OptionalAttribute("type"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", RawDescription),
    args: xml.ElementList("arg", RawArg),
};

const RawEnum = struct {
    name: xml.Attribute("name"),
    since: xml.OptionalAttribute("since"),
    bitfield: xml.OptionalAttribute("bitfield"),
    description: xml.OptionalElement("description", RawDescription),
    entries: xml.ElementList("entry", RawEntry),
};

const RawEntry = struct {
    name: xml.Attribute("name"),
    value: xml.Attribute("value"),
    summary: xml.OptionalAttribute("summary"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", RawDescription),
};

const RawArg = struct {
    name: xml.Attribute("name"),
    type: xml.Attribute("type"),
    summary: xml.OptionalAttribute("summary"),
    interface: xml.OptionalAttribute("interface"),
    allow_null: xml.OptionalAttribute("allow-null"),
    @"enum": xml.OptionalAttribute("enum"),
    description: xml.OptionalElement("description", RawDescription),
};

const RawDescription = struct {
    summary: xml.Attribute("summary"),
    body: xml.String,
};

const RawCopyright = struct {
    body: xml.String,
};

const CodegenMode = enum {
    client,
    server,
};
