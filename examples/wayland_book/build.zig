const std = @import("std");

const protocols = .{
    .{
        "stable/xdg-shell/xdg-shell.xml",
        "xdg_",
    },
    .{
        "experimental/xx-session-management/xx-session-management-v1.xml",
        "xx_",
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});

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
    run_scanner.addArg("-m client");
    inline for (protocols) |p| {
        run_scanner.addArgs(&.{ "-p ", p[1], p[0] });
    }
    const protocol_root_source_file = run_scanner.addPrefixedOutputFileArg(
        "-o ",
        "client_protocol.zig",
    );
    const protocol_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = protocol_root_source_file,
    });
    protocol_mod.addImport("zwl", wayland.module("wayland"));
    exe.root_module.addImport("protocol", protocol_mod);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run wayland book exe.");
    run_step.dependOn(&run_exe.step);
}
