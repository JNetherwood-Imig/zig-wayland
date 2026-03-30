const std = @import("std");
const protocol = @import("build/protocol.zig");

pub fn build(b: *std.Build) void {
    const xml_dep = b.dependency("xml", .{});
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_protocols_dep = b.dependency("wayland_protocols", .{});
    const wlr_protocols_dep = b.dependency("wlr_protocols", .{});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = makeScanner(b, target, optimize, xml_dep);

    const test_step = b.step("test", "Test core functions and perform " ++
        "semantic analysis on whole codebase, plus generated protocols.");

    const core = b.addModule("wayland_core", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/wayland_core.zig"),
    });
    const core_tests = b.addTest(.{ .root_module = core });
    const run_core_tests = b.addRunArtifact(core_tests);
    test_step.dependOn(&run_core_tests.step);

    const doc_generator = b.addExecutable(.{
        .name = "gen-docs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("build/generate_docs.zig"),
        }),
    });
    const gen_docs = b.addRunArtifact(doc_generator);
    const docs = gen_docs.addOutputFileArg("wayland.zig");

    const doc_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = docs,
    });

    doc_mod.addImport("wayland_core", core);

    const doc_object = b.addObject(.{
        .name = "wayland",
        .root_module = doc_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = doc_object.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const check_exe = b.addObject(.{ .name = "check", .root_module = core });
    const check_step = b.step("check", "ZLS check.");
    check_step.dependOn(&check_exe.step);

    const dep_dir = makeProtocolDeps(
        b,
        scanner,
        wayland_dep,
        wayland_protocols_dep,
        wlr_protocols_dep,
    );

    makeProtocols(
        b,
        target,
        optimize,
        core,
        test_step,
        doc_mod,
        dep_dir,
        scanner,
        wayland_dep,
        wayland_protocols_dep,
        wlr_protocols_dep,
    );
}

pub const ProtocolSide = enum { client, server };

pub fn generateDependencyInfo(
    b: *std.Build,
    scanner: *std.Build.Step.Compile,
    protocol_xml: std.Build.LazyPath,
    prefix_to_strip: []const u8,
    output_file_name: []const u8,
) std.Build.LazyPath {
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArg("dep_info");
    run_scanner.addFileArg(protocol_xml);
    run_scanner.addArgs(&.{ "-p", prefix_to_strip, "-o" });
    return run_scanner.addOutputFileArg(output_file_name);
}

pub fn generateProtocol(
    b: *std.Build,
    scanner: *std.Build.Step.Compile,
    protocol_xml: std.Build.LazyPath,
    prefix_to_strip: []const u8,
    output_file_name: []const u8,
    imports: []const std.Build.LazyPath,
    side: ProtocolSide,
) std.Build.LazyPath {
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArg(@tagName(side));
    run_scanner.addFileArg(protocol_xml);
    run_scanner.addArgs(&.{ "-p", prefix_to_strip });
    for (imports) |import| {
        run_scanner.addArg("-i");
        run_scanner.addFileArg(import);
    }
    run_scanner.addArg("-o");
    return run_scanner.addOutputFileArg(output_file_name);
}

fn makeScanner(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    xml_dep: *std.Build.Dependency,
) *std.Build.Step.Compile {
    const scanner = b.addExecutable(.{
        .name = "scanner",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("scanner/main.zig"),
        }),
    });
    scanner.root_module.addImport("xml", xml_dep.module("xml"));
    b.installArtifact(scanner);
    return scanner;
}

fn makeProtocolDeps(
    b: *std.Build,
    scanner: *std.Build.Step.Compile,
    wayland_dep: *std.Build.Dependency,
    wayland_protocols_dep: *std.Build.Dependency,
    wlr_protocols_dep: *std.Build.Dependency,
) *std.Build.Step.WriteFile {
    const dep_dir = b.addWriteFiles();
    writeDepSet(b, dep_dir, scanner, wayland_dep, protocol.core);
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.stable);
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.staging);
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.unstable);
    writeDepSet(b, dep_dir, scanner, wayland_protocols_dep, protocol.experimental);
    writeDepSet(b, dep_dir, scanner, wlr_protocols_dep, protocol.wlr);
    return dep_dir;
}

fn makeProtocols(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    test_step: *std.Build.Step,
    doc_mod: *std.Build.Module,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    wl: *std.Build.Dependency,
    wlp: *std.Build.Dependency,
    wlr: *std.Build.Dependency,
) void {
    inline for (.{ ProtocolSide.client, ProtocolSide.server }) |side| {
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wl, protocol.core, side);
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wlp, protocol.stable, side);
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wlp, protocol.staging, side);
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wlp, protocol.unstable, side);
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wlp, protocol.experimental, side);
        writeCodeSet(b, target, optimize, core, test_step, doc_mod, scanner, dep_dir, wlr, protocol.wlr, side);
    }
}

fn writeDepSet(
    b: *std.Build,
    dep_dir: *std.Build.Step.WriteFile,
    scanner: *std.Build.Step.Compile,
    protocol_source: *std.Build.Dependency,
    comptime protocol_set: type,
) void {
    inline for (@typeInfo(protocol_set).@"struct".decls) |decl| {
        const protocol_field = @field(protocol_set, decl.name);
        const generated = generateDependencyInfo(
            b,
            scanner,
            protocol_source.path(protocol_field.subpath),
            protocol_field.strip_prefix,
            decl.name ++ ".dep",
        );
        b.addNamedLazyPath(decl.name ++ "_dep", generated);
        _ = dep_dir.addCopyFile(generated, decl.name ++ ".dep");
    }
}

fn writeCodeSet(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    wayland_core: *std.Build.Module,
    test_step: *std.Build.Step,
    doc_mod: *std.Build.Module,
    scanner: *std.Build.Step.Compile,
    dep_dir: *std.Build.Step.WriteFile,
    protocol_source: *std.Build.Dependency,
    comptime protocol_set: type,
    comptime side: ProtocolSide,
) void {
    inline for (@typeInfo(protocol_set).@"struct".decls) |decl| {
        const protocol_field = @field(protocol_set, decl.name);

        const import_type = @typeInfo(@TypeOf(protocol_field.imports)).pointer.child;
        var imports: [std.meta.fields(import_type).len]std.Build.LazyPath = undefined;
        inline for (protocol_field.imports, 0..) |import, i| {
            imports[i] = dep_dir.getDirectory().path(b, import ++ ".dep");
        }

        const generated = generateProtocol(
            b,
            scanner,
            protocol_source.path(protocol_field.subpath),
            protocol_field.strip_prefix,
            decl.name ++ ".zig",
            &imports,
            side,
        );

        const name = decl.name ++ "_" ++ @tagName(side) ++ "_protocol";
        const mod = b.addModule(name, .{
            .target = target,
            .optimize = optimize,
            .root_source_file = generated,
        });
        mod.addImport("core", wayland_core);
        inline for (protocol_field.imports) |import| mod.addImport(
            import,
            b.modules.get(import ++ "_" ++ @tagName(side) ++ "_protocol").?,
        );

        const test_exe = b.addTest(.{ .root_module = mod });
        const run_test_exe = b.addRunArtifact(test_exe);
        test_step.dependOn(&run_test_exe.step);

        doc_mod.addAnonymousImport(name, .{
            .target = target,
            .optimize = optimize,
            .root_source_file = generated,
        });
    }
}

// fn genWaylandProtocols() void {
//     const definitions = @import("build/protocol2.zig");
//     inline for (@typeInfo(definitions).@"struct".decls) |namespace| {
//         const protocol_group = @field(definitions, namespace.name);
//         const protocols = @typeInfo(@TypeOf(protocol_group)).@"struct".fields;
//         inline for (protocols) |protocol_| {
//             const name = protocol_.name;
//             const data = @field(protocol_group, name);
//             const versions: []const comptime_int = data.@"0";
//             const dependencies: []const []const u8 = data.@"1" ++ [_][]const u8{"wayland"};

//             if (versions.len == 0) {
//                 const path = std.fmt.comptimePrint("{s}/{s}/{s}.xml", .{ namespace.name, name, name });
//             } else inline for (versions) |version| {
//                 const path = std.fmt.comptimePrint("{s}/{s}/{s}-v{d}.xml", .{ namespace.name, name, name, version });
//             }
//         }
//     }
// }

// fn makeDep(
//     b: *std.Build,
//     scanner: *std.Build.Step.Compile,
//     input_file: std.Build.LazyPath,
//     prefix: []const u8,
//     comptime output_name: []const u8,
// ) void {
//     const run = b.addRunArtifact(scanner);
//     run.addFileArg(input_file);
//     run.addArgs(&.{ "-p", prefix, "-o" });
//     const output_file = run.addOutputFileArg(output_name ++ ".zig");
//     b.addNamedLazyPath(output_name ++ "-dep", output_file);
// }

// fn makeCode(
//     b: *std.Build,
//     scanner: *std.Build.Step.Compile,
//     input_file: std.Build.LazyPath,
//     prefix: []const u8,
//     comptime output_name: []const u8,
//     comptime dependencies: []const []const u8,
// ) void {

//     }
