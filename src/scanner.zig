const std = @import("std");
const xml = @import("xml");
const log = std.log.scoped(.scanner);
const Allocator = std.mem.Allocator;

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

    if (output_path) |path| {
        const output_file = try std.fs.cwd().createFile(path, .{});
        defer output_file.close();

        var output_buffer: [4096]u8 = undefined;
        var file_writer = output_file.writer(&output_buffer);
        const writer = &file_writer.interface;

        try context.write(gpa, writer);

        try writer.flush();
    }
}

const Context = struct {
    protocols: std.ArrayList(Protocol),

    pub fn init(gpa: Allocator) !Context {
        return .{
            .protocols = try .initCapacity(gpa, 4),
        };
    }

    pub fn deinit(self: *Context, gpa: Allocator) void {
        for (self.protocols.items) |*protocol|
            protocol.deinit(gpa);
        self.protocols.deinit(gpa);
    }

    fn parseDocument(self: *Context, gpa: Allocator, reader: *xml.Reader, prefix: []const u8) !void {
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

    pub fn write(self: *const Context, gpa: Allocator, writer: *std.Io.Writer) !void {
        try writer.writeAll("const core = @import(\"core\");\n");
        try writer.writeAll("const Fixed = core.Fixed;\n");
        try writer.writeAll("const Connection = core.Connection;\n");
        try writer.writeAll("const IdAllocator = core.IdAllocator;\n");

        for (self.protocols.items) |protocol| {
            try writer.print("pub const {s} = struct {{\n", .{protocol.name});
            for (protocol.interfaces.items) |interface| {
                // Quick and dirty unchecked prefix stripping
                const type_name = try typeName(gpa, interface.name[protocol.prefix.len..]);
                defer gpa.free(type_name);

                try writer.print("\tpub const {s} = enum(u32) {{\n", .{type_name});
                try writer.writeAll("\t\t_,\n");
                try writer.print(
                    "\t\tpub fn id(self: {s}) u32 {{\n\t\t\treturn @intFromEnum(self);\n\t\t}}\n",
                    .{type_name},
                );
                for (interface.requests.items, 0..) |request, i| {
                    const fn_name = try fnName(gpa, request.name);
                    defer gpa.free(fn_name);

                    const max_length = request.calculateMaxLength();
                    try writer.print("\t\tpub const {s}_request_opcode = {d};\n", .{ request.name, i });
                    try writer.print("\t\tpub const {s}_request_length = {d};\n", .{ request.name, max_length });

                    try writer.print("\t\tpub fn {s}(\n", .{fn_name});
                    try writer.print("\t\t\tself: {s}\n", .{type_name});
                    try writer.print("\t\t) !{s} {{\n", .{"void"});
                    try writer.writeAll("\t\t\t_ = self;\n");
                    try writer.writeAll("\t\t}\n");
                }
                try writer.writeAll("\t};\n");
            }
            try writer.writeAll("};\n");
        }
    }

    fn typeName(gpa: Allocator, name: []const u8) ![]const u8 {
        var output = try std.ArrayList(u8).initCapacity(gpa, name.len);
        var it = std.mem.tokenizeScalar(u8, name, '_');

        while (it.next()) |tok| {
            output.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
            if (tok.len > 1) output.appendSliceAssumeCapacity(tok[1..]);
        }

        return try output.toOwnedSlice(gpa);
    }

    fn fnName(gpa: Allocator, name: []const u8) ![]const u8 {
        // Request name is a zig idenitfier, such as `error` or `type` and needs to be wrapped with @"..."
        if (!std.zig.isValidId(name))
            return fnNameInvalid(gpa, name);

        var output = try std.ArrayList(u8).initCapacity(gpa, name.len);
        var it = std.mem.tokenizeScalar(u8, name, '_');

        // Since functions are camelCase, append the fist token without making it upper case
        const first_tok = it.next().?;
        output.appendSliceAssumeCapacity(first_tok);

        while (it.next()) |tok| {
            output.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
            if (tok.len > 1) output.appendSliceAssumeCapacity(tok[1..]);
        }
        return try output.toOwnedSlice(gpa);
    }

    fn fnNameInvalid(gpa: Allocator, name: []const u8) ![]const u8 {
        var output = try std.ArrayList(u8).initCapacity(gpa, name.len + 3);
        output.appendSliceAssumeCapacity("@\"");
        var it = std.mem.tokenizeScalar(u8, name, '_');
        const first_tok = it.next().?;
        output.appendSliceAssumeCapacity(first_tok);
        while (it.next()) |tok| {
            output.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
            if (tok.len > 1) output.appendSliceAssumeCapacity(tok[1..]);
        }
        output.appendAssumeCapacity('"');
        return try output.toOwnedSlice(gpa);
    }

    const Protocol = struct {
        prefix: []const u8,
        name: []const u8,
        description: ?Description = null,
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

            var interfaces = try std.ArrayList(Interface).initCapacity(gpa, 4);
            errdefer interfaces.deinit(gpa);

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const elem = reader.elementName();
                    if (std.mem.eql(u8, elem, "copyright"))
                        continue
                    else if (!std.mem.eql(u8, elem, "protocol"))
                        return error.UnexpectedElementEnd;
                    break;
                },
                .element_start => {
                    const elem = reader.elementName();
                    if (std.mem.eql(u8, elem, "copyright"))
                        continue
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
                .interfaces = interfaces,
            };
        }

        pub fn deinit(self: *Protocol, gpa: Allocator) void {
            if (self.description) |*d| d.deinit(gpa);
            for (self.interfaces.items) |*i| i.deinit(gpa);
            self.interfaces.deinit(gpa);
            gpa.free(self.prefix);
            gpa.free(self.name);
        }
    };

    const Interface = struct {
        name: []const u8,
        version: u32,
        description: ?Description = null,
        requests: std.ArrayList(Request),
        events: std.ArrayList(Event),
        enums: std.ArrayList(Enum),

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Interface {
            var name: ?[]const u8 = null;
            errdefer if (name) |n| gpa.free(n);
            var version: ?u32 = null;

            for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (std.mem.eql(u8, attrib, "name"))
                    name = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "version"))
                    version = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
                else
                    continue;
            }

            var description: ?Description = null;
            errdefer if (description) |*desc| desc.deinit(gpa);

            var requests = try std.ArrayList(Request).initCapacity(gpa, 8);
            errdefer {
                for (requests.items) |*req| req.deinit(gpa);
                requests.deinit(gpa);
            }

            var events = try std.ArrayList(Event).initCapacity(gpa, 8);
            errdefer {
                for (events.items) |*ev| ev.deinit(gpa);
                events.deinit(gpa);
            }

            var enums = try std.ArrayList(Enum).initCapacity(gpa, 4);
            errdefer {
                for (enums.items) |*en| en.deinit(gpa);
                enums.deinit(gpa);
            }

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "interface"))
                        return error.UnexpectedElementEnd;
                    break;
                },
                .element_start => {
                    const elem = reader.elementName();
                    if (std.mem.eql(u8, elem, "description")) {
                        description = try Description.parse(gpa, reader);
                    } else if (std.mem.eql(u8, elem, "request")) {
                        var request = try Request.parse(gpa, reader);
                        errdefer request.deinit(gpa);
                        try requests.append(gpa, request);
                    } else if (std.mem.eql(u8, elem, "event")) {
                        var event = try Event.parse(gpa, reader);
                        errdefer event.deinit(gpa);
                        try events.append(gpa, event);
                    } else if (std.mem.eql(u8, elem, "enum")) {
                        var en = try Enum.parse(gpa, reader);
                        errdefer en.deinit(gpa);
                        try enums.append(gpa, en);
                    } else return error.UnexpectedElement;
                },
                else => continue,
            } else |err| return err;

            return .{
                .name = name orelse return error.NameNotFound,
                .version = version orelse return error.VersionNotFound,
                .description = description,
                .requests = requests,
                .events = events,
                .enums = enums,
            };
        }

        pub fn deinit(self: *Interface, gpa: Allocator) void {
            gpa.free(self.name);
            if (self.description) |*desc| desc.deinit(gpa);
            for (self.requests.items) |*req| req.deinit(gpa);
            for (self.events.items) |*ev| ev.deinit(gpa);
            for (self.enums.items) |*en| en.deinit(gpa);
            self.requests.deinit(gpa);
            self.events.deinit(gpa);
            self.enums.deinit(gpa);
        }
    };

    const Request = struct {
        name: []const u8,
        type: enum { none, destructor } = .none,
        since: u32,
        deprecated_since: ?u32,
        description: ?Description,
        args: std.ArrayList(Arg),

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Request {
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
                    if (!std.mem.eql(u8, elem, "request"))
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

        pub fn deinit(self: *Request, gpa: Allocator) void {
            gpa.free(self.name);
            if (self.description) |*desc| desc.deinit(gpa);
            for (self.args.items) |*arg| arg.deinit(gpa);
            self.args.deinit(gpa);
        }

        pub fn calculateMaxLength(self: *const Request) usize {
            var length: usize = 8; // Start at size of message header

            for (self.args.items) |arg| switch (arg.type) {
                // Strings and arrays have an undefined size,
                // so we can only assume the maximum capacity, as asserted by libwayland
                .array, .string, .optional_string, .any_new_id => return 4096,
                // Fds are not serialized on the wire, but sent via ancillary
                .fd => {},
                // Everything else is serialized as a 32 bit integer
                else => length += 4,
            };

            return length;
        }
    };

    const Event = struct {
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
    };

    const Enum = struct {
        name: []const u8,
        since: u32,
        type: enum { none, bitfield } = .none,
        description: ?Description = null,
        entries: std.ArrayList(Entry),

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Enum {
            var name: ?[]const u8 = null;
            var since: ?u32 = null;
            var is_bitfield = false;

            for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (std.mem.eql(u8, attrib, "name"))
                    name = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "since"))
                    since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
                else if (std.mem.eql(u8, attrib, "bitfield"))
                    is_bitfield = std.mem.eql(u8, reader.attributeValueRaw(i), "true")
                else
                    return error.UnexpectedAttribute;
            }

            var entries = try std.ArrayList(Entry).initCapacity(gpa, 8);
            errdefer {
                for (entries.items) |*ent| ent.deinit(gpa);
                entries.deinit(gpa);
            }

            var description: ?Description = null;

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "enum"))
                        return error.UnexpectedElementEnd;
                    break;
                },
                .element_start => {
                    const elem = reader.elementName();
                    if (std.mem.eql(u8, elem, "description"))
                        description = try Description.parse(gpa, reader)
                    else if (std.mem.eql(u8, elem, "entry")) {
                        var entry = try Entry.parse(gpa, reader);
                        errdefer entry.deinit(gpa);
                        try entries.append(gpa, entry);
                    } else return error.UnexpectedElement;
                },
                else => continue,
            } else |err| return err;

            return .{
                .name = name orelse return error.NameNotFound,
                .since = since orelse 1,
                .type = if (is_bitfield) .bitfield else .none,
                .description = description,
                .entries = entries,
            };
        }

        pub fn deinit(self: *Enum, gpa: Allocator) void {
            for (self.entries.items) |*entry| entry.deinit(gpa);
            self.entries.deinit(gpa);
            if (self.description) |*d| d.deinit(gpa);
            gpa.free(self.name);
        }
    };

    const Entry = struct {
        name: []const u8,
        value: u32,
        summary: ?[]const u8,
        since: u32,
        deprecated_since: ?u32,
        description: ?Description,

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Entry {
            var name: ?[]const u8 = null;
            errdefer if (name) |n| gpa.free(n);
            var summary: ?[]const u8 = null;
            errdefer if (summary) |s| gpa.free(s);

            var value: ?u32 = null;
            var since: ?u32 = null;
            var deprecated_since: ?u32 = null;

            for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (std.mem.eql(u8, attrib, "name"))
                    name = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "summary"))
                    summary = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "since"))
                    since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
                else if (std.mem.eql(u8, attrib, "deprecated-since"))
                    deprecated_since = try std.fmt.parseInt(u32, reader.attributeValueRaw(i), 10)
                else if (std.mem.eql(u8, attrib, "value")) {
                    const raw_value = reader.attributeValueRaw(i);
                    value = if (std.mem.startsWith(u8, raw_value, "0x"))
                        try std.fmt.parseInt(u32, raw_value[2..], 16)
                    else
                        try std.fmt.parseInt(u32, raw_value, 10);
                } else return error.UnexpectedAttribute;
            }

            var description: ?Description = null;

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "entry"))
                        return error.UnexpectedElement;
                    break;
                },
                .element_start => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "description"))
                        return error.UnexpectedElement;
                    description = try Description.parse(gpa, reader);
                },
                else => continue,
            } else |err| return err;

            return .{
                .name = name orelse return error.NameNotFound,
                .value = value orelse return error.ValueNotFound,
                .since = since orelse 1,
                .deprecated_since = deprecated_since,
                .summary = summary,
                .description = description,
            };
        }

        pub fn deinit(self: *Entry, gpa: Allocator) void {
            if (self.description) |*desc| desc.deinit(gpa);
            if (self.summary) |s| gpa.free(s);
            gpa.free(self.name);
        }
    };

    const Arg = struct {
        name: []const u8,
        type: Type,
        summary: ?[]const u8,
        description: ?Description,

        const Type = union(enum) {
            int: void,
            uint: void,
            fixed: void,
            string: void,
            optional_string: void,
            array: void,
            fd: void,
            any_object: void,
            any_optional_object: void,
            any_new_id: void,
            @"enum": []const u8,
            object: []const u8,
            optional_object: []const u8,
            new_id: []const u8,

            fn resolve(str: []const u8, allow_null: bool, interface: ?[]const u8, en: ?[]const u8) !Type {
                if (std.mem.eql(u8, str, "fixed"))
                    return .fixed
                else if (std.mem.eql(u8, str, "string"))
                    return if (allow_null) .optional_string else .string
                else if (std.mem.eql(u8, str, "array"))
                    return .array
                else if (std.mem.eql(u8, str, "fd"))
                    return .fd
                else if (std.mem.eql(u8, str, "int"))
                    return if (en) |e| .{ .@"enum" = e } else .int
                else if (std.mem.eql(u8, str, "uint"))
                    return if (en) |e| .{ .@"enum" = e } else .uint
                else if (std.mem.eql(u8, str, "new_id"))
                    return if (interface) |i| .{ .new_id = i } else .any_new_id
                else if (std.mem.eql(u8, str, "object"))
                    if (interface) |i|
                        return if (allow_null) .{ .optional_object = i } else .{ .object = i }
                    else
                        return if (allow_null) .any_optional_object else .any_object
                else
                    return error.UnknownArgType;
            }
        };

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Arg {
            var name: ?[]const u8 = null;
            errdefer if (name) |n| gpa.free(n);
            var summary: ?[]const u8 = null;
            errdefer if (summary) |sum| gpa.free(sum);

            var type_str: ?[]const u8 = null;
            defer if (type_str) |t| gpa.free(t);

            var allow_null: bool = false;
            var interface: ?[]const u8 = null;
            errdefer if (interface) |i| gpa.free(i);
            var en: ?[]const u8 = null;
            errdefer if (en) |e| gpa.free(e);

            for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (std.mem.eql(u8, attrib, "name"))
                    name = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "type"))
                    type_str = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "summary"))
                    summary = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "interface"))
                    interface = try reader.attributeValueAlloc(gpa, i)
                else if (std.mem.eql(u8, attrib, "allow-null"))
                    allow_null = std.mem.eql(u8, reader.attributeValueRaw(i), "true")
                else if (std.mem.eql(u8, attrib, "enum"))
                    en = try reader.attributeValueAlloc(gpa, i)
                else
                    return error.UnexpectedArgAttribute;
            }

            var description: ?Description = null;

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "arg"))
                        return error.UnexpectedElementEnd;
                    break;
                },
                .element_start => {
                    const elem = reader.elementName();
                    if (!std.mem.eql(u8, elem, "description"))
                        return error.UnexpectedArgElement;
                    description = try Description.parse(gpa, reader);
                },
                else => continue,
            } else |err| return err;

            return .{
                .name = name orelse return error.NameNotFound,
                .summary = summary,
                .description = description,
                .type = try .resolve(type_str orelse return error.TypeNotFound, allow_null, interface, en),
            };
        }

        pub fn deinit(self: *Arg, gpa: Allocator) void {
            gpa.free(self.name);
            if (self.summary) |sum| gpa.free(sum);
            if (self.description) |*desc| desc.deinit(gpa);

            switch (self.type) {
                inline .@"enum", .object, .optional_object, .new_id => |str| gpa.free(str),
                else => {},
            }
        }

        pub fn typeString(self: *const Arg) []const u8 {
            return switch (self.type) {
                .int => "i32",
                .uint => "u32",
                .fixed => "Fixed",
                .any_object => "u32",
                .any_new_id => "u32",
            };
        }
    };

    const Description = struct {
        summary: []const u8,
        body: ?[]const u8 = null,

        pub fn parse(gpa: Allocator, reader: *xml.Reader) !Description {
            const summary = for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (!std.mem.eql(u8, attrib, "summary")) continue;
                break try reader.attributeValueAlloc(gpa, i);
            } else return error.SummaryNotFound;
            errdefer gpa.free(summary);

            var body: ?[]const u8 = null;
            errdefer if (body) |b| gpa.free(b);

            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const name = reader.elementName();
                    if (!std.mem.eql(u8, name, "description")) return error.UnexpectedElementEnd;
                    break;
                },
                .text => {
                    body = try gpa.dupe(u8, reader.textRaw());
                },
                else => continue,
            } else |err| return err;

            return .{ .summary = summary, .body = body };
        }

        pub fn deinit(self: *Description, gpa: Allocator) void {
            gpa.free(self.summary);
            if (self.body) |body| gpa.free(body);
        }
    };
};

const Mode = enum {
    client,
    server,
};
