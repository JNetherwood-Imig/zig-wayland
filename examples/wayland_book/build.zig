const std = @import("std");

const protocols = .{
    .{
        "stable/xdg-shell/xdg-shell.xml",
        "xdg_",
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});
    const wayland_xml = b.dependency("wayland-xml", .{});
    const wayland_protocols = b.dependency("wayland-protocols", .{});

    const exe = b.addExecutable(.{
        .name = "wayland_book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("zwl", wayland.module("wayland"));
    b.installArtifact(exe);

    const scanner = wayland.artifact("scanner");
    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArgs(&.{ "-m", "client" });
    run_scanner.addArgs(&.{ "-p", "wl_" });
    run_scanner.addFileArg(wayland_xml.path("protocol/wayland.xml"));
    inline for (protocols) |p| {
        run_scanner.addArgs(&.{ "-p", p[1] });
        run_scanner.addFileArg(wayland_protocols.path(p[0]));
    }
    run_scanner.addArg("-o");
    const protocol_root_source_file = run_scanner.addOutputFileArg(
        "client_protocol.zig",
    );
    const protocol_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = protocol_root_source_file,
    });
    protocol_mod.addImport("core", wayland.module("wayland"));
    exe.root_module.addImport("protocol", protocol_mod);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run wayland book exe.");
    run_step.dependOn(&run_exe.step);
}
