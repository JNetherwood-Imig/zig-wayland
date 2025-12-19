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

    const core_tests = b.addTest(.{ .root_module = core });
    const run_core_tests = b.addRunArtifact(core_tests);
    const test_step = b.step("test", "Test everything!!!");
    test_step.dependOn(&run_core_tests.step);

    writeCodeSet(
        b,
        target,
        optimize,
        core,
        test_step,
        scanner,
        dep_dir,
        wayland_dep,
        protocol.core,
        "protocol",
        .client,
    );

    writeCodeSet(
        b,
        target,
        optimize,
        core,
        test_step,
        scanner,
        dep_dir,
        wayland_protocols_dep,
        protocol.stable,
        "stable",
        .client,
    );
    writeCodeSet(
        b,
        target,
        optimize,
        core,
        test_step,
        scanner,
        dep_dir,
        wayland_protocols_dep,
        protocol.staging,
        "staging",
        .client,
    );
    writeCodeSet(
        b,
        target,
        optimize,
        core,
        test_step,
        scanner,
        dep_dir,
        wayland_protocols_dep,
        protocol.unstable,
        "unstable",
        .client,
    );
    writeCodeSet(
        b,
        target,
        optimize,
        core,
        test_step,
        scanner,
        dep_dir,
        wlr_protocols_dep,
        protocol.wlr,
        "unstable",
        .client,
    );
}

fn writeCodeSet(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    test_step: *std.Build.Step,
    scanner: *std.Build.Step.Compile,
    dep_dir: *std.Build.Step.WriteFile,
    protocol_source: *std.Build.Dependency,
    comptime protocol_set: type,
    comptime subdir: []const u8,
    comptime side: Side,
) void {
    inline for (@typeInfo(protocol_set).@"struct".decls) |decl| {
        const protocol_field = @field(protocol_set, decl.name);
        writeCode(
            b,
            target,
            optimize,
            core,
            test_step,
            dep_dir,
            scanner,
            protocol_source.path(subdir).path(b, protocol_field.subpath),
            protocol_field.strip_prefix,
            decl.name,
            protocol_field.imports,
            side,
        );
    }
}

fn writeCode(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    test_step: *std.Build.Step,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    input_path: std.Build.LazyPath,
    prefix: []const u8,
    comptime name: []const u8,
    comptime imports: []const []const u8,
    comptime side: Side,
) void {
    const output_name = name ++ "_" ++ @tagName(side) ++ "_protocol";
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
    const mod = b.addModule(output_name, .{
        .target = target,
        .optimize = optimize,
        .root_source_file = output,
    });
    mod.addImport("core", core);
    inline for (imports) |import| {
        mod.addImport(import, b.modules.get(import ++ "_" ++ @tagName(side) ++ "_protocol").?);
    }
    const test_exe = b.addTest(.{ .root_module = mod });
    const run_test_exe = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_test_exe.step);
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
