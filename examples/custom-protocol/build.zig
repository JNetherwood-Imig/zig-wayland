const std = @import("std");
const wayland = @import("wayland");

pub fn build(b: *std.Build) void {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_core = wayland_dep.module("wayland_core");
    const wayland_scanner = wayland_dep.artifact("wayland_scanner");
    const wayland_client_protocol = wayland_dep.module("wayland_client_protocol");
    const wayland_protocol_dep_info = wayland_dep.namedLazyPath("wayland_dep");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hyprland_surface_v1_code = wayland.generateProtocol(
        b,
        wayland_scanner,
        b.path("hyprland-surface-v1.xml"),
        "hyprland",
        "hyprland_surface_v1.zig",
        &.{wayland_protocol_dep_info},
        .client,
    );

    const hyprland_surface_v1 = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = hyprland_surface_v1_code,
    });
    hyprland_surface_v1.addImport("core", wayland_core);
    hyprland_surface_v1.addImport("wayland", wayland_client_protocol);

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("wayland", wayland_core);
    exe.root_module.addImport("wayland_protocol", wayland_client_protocol);
    exe.root_module.addImport("hyprland_surface", hyprland_surface_v1);
    b.installArtifact(exe);
}
