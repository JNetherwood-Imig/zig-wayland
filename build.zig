const std = @import("std");

const protocols = .{
    .{ "stable/linux-dmabuf/linux-dmabuf-v1.xml", "zwp_linux_" },
    .{ "stable/presentation-time/presentation-time.xml", "wp_" },
    .{ "stable/tablet/tablet-v2.xml", "zwp_" },
    .{ "stable/viewporter/viewporter.xml", "wp_" },
    .{ "stable/xdg-shell/xdg-shell.xml", "xdg_" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const scanner = makeScanner(b, target, optimize);

    const util = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/util.zig"),
    });

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core.zig"),
    });
    core.addImport("util", util);

    const client_protocol = makeProtoocl("client", b, target, optimize, scanner, util, core);
    const server_protocol = makeProtoocl("server", b, target, optimize, scanner, util, core);

    const client = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
    });
    client.addImport("util", util);
    client.addImport("core", core);
    client.addImport("protocol", client_protocol);

    const server = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });
    server.addImport("util", util);
    server.addImport("core", core);
    server.addImport("protocol", server_protocol);

    const client_test_exe = b.addTest(.{ .root_module = client });
    const server_test_exe = b.addTest(.{ .root_module = server });
    const run_client_test = b.addRunArtifact(client_test_exe);
    const run_server_test = b.addRunArtifact(server_test_exe);
    const test_step = b.step("test", "Run all tests.");
    test_step.dependOn(&run_client_test.step);
    test_step.dependOn(&run_server_test.step);

    const wayland_book = b.addExecutable(.{
        .name = "wayland-book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("examples/wayland_book.zig"),
        }),
    });
    wayland_book.root_module.addImport("zwl", client);
    b.installArtifact(wayland_book);
    const run_wayland_book = b.addRunArtifact(wayland_book);
    const run_wayland_book_step = b.step("run-wayland-book", "Run wayland-book example.");
    run_wayland_book_step.dependOn(&run_wayland_book.step);
}

fn makeScanner(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const xml = b.dependency("xml", .{});

    const scanner = b.addExecutable(.{
        .name = "scanner",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("scanner/scanner.zig"),
        }),
    });
    scanner.root_module.addImport("xml", xml.module("xml"));
    b.installArtifact(scanner);

    return scanner;
}

fn makeProtoocl(
    comptime side: []const u8,
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    scanner: *std.Build.Step.Compile,
    util: *std.Build.Module,
    core: *std.Build.Module,
) *std.Build.Module {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_xml = wayland_dep.path("protocol/wayland.xml");
    const wayland_protocols_dep = b.dependency("wayland_protocols", .{});

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArgs(&.{ "-p", "wl_" });
    run_scanner.addFileArg(wayland_xml);
    inline for (protocols) |protocol| {
        const prefix = protocol[1];
        run_scanner.addArgs(&.{ "-p", prefix });
        const path = wayland_protocols_dep.path(protocol[0]);
        run_scanner.addFileArg(path);
    }
    run_scanner.addArgs(&.{ "-m", side });
    run_scanner.addArg("-o");
    const output = run_scanner.addOutputFileArg(side ++ "_protocol.zig");

    return b.addModule(side ++ "_protocol", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = output,
        .imports = &.{
            .{ .name = "core", .module = core },
            .{ .name = "util", .module = util },
        },
    });
}
