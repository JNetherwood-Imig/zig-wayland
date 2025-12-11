const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const wayland = b.addModule("wayland", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/wayland.zig"),
    });

    const test_exe = b.addTest(.{ .root_module = wayland });
    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run all tests for wayland and the scanner.");
    test_step.dependOn(&run_test.step);
}
