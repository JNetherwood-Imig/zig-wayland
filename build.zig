const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("core/src/root.zig"),
    });
    const core_tests = b.addTest(.{ .root_module = core });
    const core_run_tests = b.addRunArtifact(core_tests);

    const denali = b.addModule("denali", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{.{ .name = "core", .module = core }},
    });
    const denali_tests = b.addTest(.{ .root_module = denali });
    const denali_run_tests = b.addRunArtifact(denali_tests);

    const test_step = b.step("test", "Run all tests.");
    test_step.dependOn(&core_run_tests.step);
    test_step.dependOn(&denali_run_tests.step);

    addExample(b, target, optimize, denali, "wayland_book");
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    denali: *std.Build.Module,
    comptime name: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("examples/" ++ name ++ ".zig"),
        }),
    });
    exe.root_module.addImport("denali", denali);
    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step(name, "Run " ++ name ++ " example");
    run_step.dependOn(&run_exe.step);
}
