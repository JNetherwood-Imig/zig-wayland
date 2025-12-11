const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});

    const hello_world = b.addExecutable(.{
        .name = "hello-world",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("hello-world/main.zig"),
        }),
    });
    hello_world.root_module.addImport("wayland", wayland.module("wayland_core"));
    hello_world.root_module.addImport("protocol", wayland.module("client-protocol"));
    b.installArtifact(hello_world);
}
