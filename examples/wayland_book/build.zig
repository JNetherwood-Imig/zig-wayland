const std = @import("std");

const protocols = .{
    .{
        "stable/xdg-shell/xdg-shell.xml",
        "xdg_",
    },
    .{
        "experimental/xx-session-management/xx-session-management-v1.xml",
        "xx_",
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});

    const exe = b.addExecutable(.{
        .name = "wayland_book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("zwl", wayland.module("wayland"));
    addCoreProtocol(b, exe, target, optimize);
    addExtensionProtocols(b, exe, target, optimize);
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run wayland book exe.");
    run_step.dependOn(&run_exe.step);
}

fn addExtensionProtocols(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const scanner = b.dependency("wayland", .{}).artifact("scanner");
    const wayland_protocols = b.dependency("wayland-protocols", .{});
    inline for (protocols) |p| {
        const run_scanner = b.addRunArtifact(scanner);
        run_scanner.addArg("client");
        run_scanner.addFileArg(wayland_protocols.path(p[0] ++ ".xml"));
        const generated = run_scanner.addOutputFileArg(p[0] ++ ".zig");
        run_scanner.addArg(p[2]);
        exe.root_module.addAnonymousImport(p[1], .{
            .target = target,
            .optimize = optimize,
            .root_source_file = generated,
        });
    }
}

fn addCoreProtocol(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const scanner = b.dependency("wayland", .{}).artifact("scanner");
    const wayland_xml = b.dependency("wayland-xml", .{}).path("protocol/wayland.xml");
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArg("client");
    run_scanner.addFileArg(wayland_xml);
    const generated = run_scanner.addOutputFileArg("wayland.zig");
    run_scanner.addArg("wl_");
    exe.root_module.addAnonymousImport("wayland", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = generated,
    });
}
