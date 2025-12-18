const std = @import("std");
const protocol = @import("build/protocol.zig");

pub fn build(b: *std.Build) void {
    const xml = b.dependency("xml", .{});
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_protocols_dep = b.dependency("wayland_protocols", .{});
    const wlr_protocols_dep = b.dependency("wlr_protocols", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("wayland_core", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/wayland_core.zig"),
    });

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

    const dep_dir = b.addWriteFiles();

    writeDepSet(b, dep_dir, scanner, wayland_dep, protocol.core, "protocol");
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.stable, "stable");
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.staging, "staging");
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.unstable, "unstable");
    writeDepSet(b, dep_dir, scanner, wlr_protocols_dep, protocol.wlr, "unstable");

    const gen_dep_step = b.step("deps", "Generate dependency information for protocols.");
    gen_dep_step.dependOn(&dep_dir.step);

    writeCodeSet(
        b,
        target,
        optimize,
        core,
        scanner,
        dep_dir,
        wayland_dep,
        protocol.core,
        "protocol",
        .client,
    );

    const generated = writeCode(
        b,
        dep_dir,
        scanner,
        wayland_dep.path("protocol/wayland.xml"),
        "wl",
        "wayland",
        &.{},
        .client,
    );
    const wayland_client_protocol = b.addModule("wayland_client_protocol", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = generated,
    });
    wayland_client_protocol.addImport("core", core);

    const generated_xdg_shell = writeCode(
        b,
        dep_dir,
        scanner,
        wayland_protocols_dep.path("stable/xdg-shell/xdg-shell.xml"),
        "xdg",
        "xdg_shell",
        &.{"wayland"},
        .client,
    );
    const xdg_shell_client_protocol = b.addModule("xdg_shell_client_protocol", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = generated_xdg_shell,
    });
    xdg_shell_client_protocol.addImport("core", core);
    xdg_shell_client_protocol.addImport("wayland", wayland_client_protocol);
}

fn writeCodeSet(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    scanner: *std.Build.Step.Compile,
    dep_dir: *std.Build.Step.WriteFile,
    protocol_source: *std.Build.Dependency,
    comptime protocol_set: type,
    comptime subdir: []const u8,
    comptime side: Side,
) void {
    inline for (@typeInfo(protocol_set).@"struct".decls) |decl| {
        const protocol_field = @field(protocol_set, decl.name);
        const output_name = decl.name ++ "_" ++ @tagName(side) ++ "_protocol";
        const generated = writeCode(
            b,
            dep_dir,
            scanner,
            protocol_source.path(subdir).path(b, protocol_field.subpath),
            protocol_field.strip_prefix,
            decl.name,
            &.{},
            side,
        );
        const mod = b.addModule(output_name, .{
            .target = target,
            .optimize = optimize,
            .root_source_file = generated,
        });
        mod.addImport("core", core);
    }
}

fn writeCode(
    b: *std.Build,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    input_path: std.Build.LazyPath,
    prefix: []const u8,
    comptime name: []const u8,
    comptime imports: []const []const u8,
    comptime side: Side,
) std.Build.LazyPath {
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArg(@tagName(side) ++ "_code");
    run_scanner.addFileArg(input_path);
    run_scanner.addArgs(&.{ "-p", prefix });
    run_scanner.addArg("-o");
    const output = run_scanner.addOutputFileArg(name ++ ".zig");
    inline for (imports) |import| {
        run_scanner.addArg("-i");
        const path = dep_dir.getDirectory().path(b, import ++ ".dep");
        run_scanner.addFileArg(path);
    }
    return output;
}

fn writeDepSet(
    b: *std.Build,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    protocol_source: *std.Build.Dependency,
    comptime protocol_set: type,
    comptime subdir: []const u8,
) void {
    inline for (@typeInfo(protocol_set).@"struct".decls) |decl| {
        const protocol_field = @field(protocol_set, decl.name);
        writeDep(
            b,
            dep_dir,
            scanner,
            protocol_source.path(subdir).path(b, protocol_field.subpath),
            protocol_field.strip_prefix,
            decl.name,
        );
    }
}

fn writeDep(
    b: *std.Build,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    input_path: std.Build.LazyPath,
    prefix: []const u8,
    comptime name: []const u8,
) void {
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArg("dep_info");
    run_scanner.addFileArg(input_path);
    run_scanner.addArgs(&.{ "-p", prefix });
    run_scanner.addArg("-o");
    const output = run_scanner.addOutputFileArg(name ++ ".dep");
    _ = dep_dir.addCopyFile(output, name ++ ".dep");
}

const Side = enum { client, server };
