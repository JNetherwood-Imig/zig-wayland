const std = @import("std");
const protocol = @import("protocol.zig");
const prelude = @embedFile("docs_prelude.txt");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();

    const output_path = args.next() orelse return error.ExpectedOutputPath;
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    var buf: [4096]u8 = undefined;
    var writer = output_file.writer(&buf);
    const w = &writer.interface;

    try emitPrelude(w);
    try w.writeAll("pub const wayland_core = @import(\"wayland_core\");\n\n");
    inline for (.{ "client", "server" }) |side| try emitProtocols(w, side);
    try w.flush();
}

fn emitPrelude(w: *std.Io.Writer) !void {
    var it = std.mem.splitScalar(u8, prelude, '\n');
    while (it.next()) |line| try w.print("//! {s}\n", .{line});
}

fn emitProtocols(w: *std.Io.Writer, side: []const u8) !void {
    try w.print("pub const {s}_protocol = struct {{\n", .{side});
    inline for (@typeInfo(protocol).@"struct".decls) |set_decl| {
        const set = @field(protocol, set_decl.name);
        inline for (@typeInfo(set).@"struct".decls) |protocol_decl| {
            const name = protocol_decl.name;
            try w.print("\tpub const {s} = @import(\"{s}_{s}_protocol\");\n\n", .{
                name,
                name,
                side,
            });
        }
    }
    try w.writeAll("};\n\n");
}
