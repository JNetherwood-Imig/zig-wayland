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
            .eof => return error.UnexpectedEof,
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
                .element_start => {
                    const elem = reader.elementName();
                    if (std.mem.eql(u8, elem, "description"))
                        description = try Description.parse(reader, gpa)
                    else if (std.mem.eql(u8, elem, "copyright"))
                        continue
                    else if (std.mem.eql(u8, elem, "interface")) {
                        var interface = try Interface.parse(gpa);
                        errdefer interface.deinit(gpa);
                        try interfaces.append(gpa, interface);
                    } else {
                        log.err("Unexpected protocol element {s}.", .{elem});
                        return error.UnexpectedElement;
                    }
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
            gpa.free(self.prefix);
            gpa.free(self.name);
            if (self.description) |*description| description.deinit(gpa);
            for (self.interfaces.items) |*interface|
                interface.deinit(gpa);
            self.interfaces.deinit(gpa);
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
        since: u32 = 1,
        deprecated_since: u32 = 0,
        description: ?Description = null,
        args: std.ArrayList(Arg),

        pub fn deinit(self: *Request, gpa: Allocator) void {
            _ = self;
            _ = gpa;
        }
    };

    const Event = struct {
        name: []const u8,
        type: enum { none, destructor } = .none,
        since: u32 = 1,
        deprecated_since: u32 = 0,
        description: ?Description = null,
        args: std.ArrayList(Arg),

        pub fn deinit(self: *Event, gpa: Allocator) void {
            _ = self;
            _ = gpa;
        }
    };

    const Enum = struct {
        name: []const u8,
        since: u32 = 1,
        type: enum { none, bitfield } = .none,
        description: ?Description = null,
        entries: std.ArrayList(Entry),

        pub fn deinit(self: *Enum, gpa: Allocator) void {
            _ = self;
            _ = gpa;
        }
    };

    const Entry = struct {
        name: []const u8,
        value: u32,
        summary: ?[]const u8 = null,
        since: u32 = 1,
        deprecated_since: u32 = 0,
        description: ?Description = null,
    };

    const Arg = struct {
        name: []const u8,
        type: Type,
        summary: ?[]const u8 = null,

        const Type = union(enum) {
            int: void,
            uint: void,
            fixed: void,
            string: void,
            optional_string: void,
            object: ?[]const u8,
            optional_object: ?[]const u8,
            new_id: ?[]const u8,
            array: void,
            fd: void,
        };
    };

    const Description = struct {
        summary: []const u8,
        body: ?[]const u8 = null,

        pub fn parse(reader: *xml.Reader, gpa: Allocator) !Description {
            const summary = for (0..reader.attributeCount()) |i| {
                const attrib = reader.attributeName(i);
                if (!std.mem.eql(u8, attrib, "summary")) continue;
                break try reader.attributeValueAlloc(gpa, i);
            } else return error.SummaryNotFound;
            errdefer gpa.free(summary);

            const body: ?[]const u8 = null;
            while (reader.read()) |node| switch (node) {
                .eof => return error.UnexpectedEof,
                .element_end => {
                    const name = reader.elementName();
                    if (!std.mem.eql(u8, name, "description")) return error.UnexpectedElementEnd;
                    break;
                },
                .text, .cdata => {
                    std.debug.print("Description body is {t}\n", .{node});
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
