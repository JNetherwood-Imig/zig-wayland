const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});
    const zwl = wayland.module("client");
    const wayland_book = b.addExecutable(.{
        .name = "wayland-book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("wayland_book.zig"),
            .link_libc = true,
        }),
    });
    wayland_book.root_module.addImport("zwl", zwl);
    b.installArtifact(wayland_book);
    const run_wayland_book = b.addRunArtifact(wayland_book);
    const run_wayland_book_step = b.step("run-wayland-book", "Run wayland book example");
    run_wayland_book_step.dependOn(&run_wayland_book.step);
}
