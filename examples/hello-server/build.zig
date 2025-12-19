const std = @import("std");

pub fn build(b: *std.Build) void {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland = wayland_dep.module("wayland_core");
    // const wayland_protocol = wayland_dep.module("wayland_server_protocol");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "hello-server",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("wayland", wayland);
    // exe.root_module.addImport("wayland_protocol", wayland_protocol);
    b.installArtifact(exe);
}
