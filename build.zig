const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland = b.addModule("wayland", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/wayland.zig"),
    });

    const scanner = makeScanner(b, target, optimize);

    const client_protocol, const server_protocol = bundleProtocols(b, target, optimize, scanner, wayland);
    _ = server_protocol;

    const test_exe = b.addTest(.{ .root_module = wayland });
    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run all tests for wayland and the scanner.");
    test_step.dependOn(&run_test.step);

    const wayland_book = b.addExecutable(.{
        .name = "wayland-book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("examples/wayland_book.zig"),
        }),
    });
    wayland_book.root_module.addImport("zwl", wayland);
    wayland_book.root_module.addImport("client_protocol", client_protocol);
    b.installArtifact(wayland_book);
    const run_wayland_book = b.addRunArtifact(wayland_book);
    const run_wayland_book_step = b.step("run-wayland-book", "Run wayland-book example.");
    run_wayland_book_step.dependOn(&run_wayland_book.step);
}

const protocols = .{
    .{ "stable/linux-dmabuf/linux-dmabuf-v1.xml", "zwp_linux_" },
    .{ "stable/presentation-time/presentation-time.xml", "wp_" },
    .{ "stable/tablet/tablet-v2.xml", "zwp_" },
    .{ "stable/viewporter/viewporter.xml", "wp_" },
    .{ "stable/xdg-shell/xdg-shell.xml", "xdg_" },
};

fn bundleProtocols(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    scanner: *std.Build.Step.Compile,
    wayland: *std.Build.Module,
) struct { *std.Build.Module, *std.Build.Module } {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_xml = wayland_dep.path("protocol/wayland.xml");
    const wayland_protocols_dep = b.dependency("wayland_protocols", .{});

    var ret: struct { *std.Build.Module, *std.Build.Module } = undefined;
    inline for (.{ "client", "server" }, 0..) |side, i| {
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

        @field(ret, std.meta.fields(@TypeOf(ret))[i].name) = b.addModule(side ++ "_protocol", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = output,
            .imports = &.{.{ .name = "core", .module = wayland }},
        });
    }

    return ret;
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
