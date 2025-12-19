const std = @import("std");

pub fn build(b: *std.Build) void {
    const wayland = b.dependency("wayland", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hello-world",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("wayland", wayland.module("wayland_core"));
    exe.root_module.addImport("wayland_protocol", wayland.module("wayland_client_protocol"));
    exe.root_module.addImport("xdg_shell", wayland.module("xdg_shell_client_protocol"));
    b.installArtifact(exe);
}
