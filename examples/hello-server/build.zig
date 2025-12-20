const std = @import("std");

pub fn build(b: *std.Build) void {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland = wayland_dep.module("wayland_core");
    const wayland_server_protocol = wayland_dep.module("wayland_server_protocol");
    const wayland_client_protocol = wayland_dep.module("wayland_client_protocol");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/server.zig"),
        }),
    });
    server.root_module.addImport("wayland", wayland);
    server.root_module.addImport("wayland_protocol", wayland_server_protocol);
    b.installArtifact(server);

    const client = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/client.zig"),
        }),
    });
    client.root_module.addImport("wayland", wayland);
    client.root_module.addImport("wayland_protocol", wayland_client_protocol);
    b.installArtifact(client);
}
