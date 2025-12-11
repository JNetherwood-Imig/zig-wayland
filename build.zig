const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const scanner = makeScanner(b, target, optimize);

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core.zig"),
    });

    const client_protocol = makeProtoocl("client", b, target, optimize, scanner, core);

    const client = b.addModule("client", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
    });
    client.addImport("core", core);
    client.addImport("client_protocol", client_protocol);

    const server_protocol = makeProtoocl("server", b, target, optimize, scanner, core);

    const server = b.addModule("server", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });
    server.addImport("core", core);
    server.addImport("server_protocol", server_protocol);

    const client_test_exe = b.addTest(.{ .root_module = client });
    const server_test_exe = b.addTest(.{ .root_module = server });
    const run_client_test = b.addRunArtifact(client_test_exe);
    const run_server_test = b.addRunArtifact(server_test_exe);
    const test_step = b.step("test", "Run all tests.");
    test_step.dependOn(&run_client_test.step);
    test_step.dependOn(&run_server_test.step);
}

fn makeScanner(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
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

    return scanner;
}

fn makeProtoocl(
    comptime side: []const u8,
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    scanner: *std.Build.Step.Compile,
    core: *std.Build.Module,
) *std.Build.Module {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_xml = wayland_dep.path("protocol/wayland.xml");
    const wayland_protocols_dep = b.dependency("wayland_protocols", .{});

    const run_scanner = b.addRunArtifact(scanner);
    run_scanner.addArgs(&.{ "-p", "wl_" });
    run_scanner.addFileArg(wayland_xml);
    inline for (protocols) |protocol| {
        const prefix = protocol[1];
        run_scanner.addArgs(&.{ "-p", prefix });
        const path = wayland_protocols_dep.path(protocol[0]);
        run_scanner.addFileArg(path);
    }
    run_scanner.addArgs(&.{ "-m", side });
    run_scanner.addArg("-o");
    const output = run_scanner.addOutputFileArg(side ++ "_protocol.zig");

    return b.addModule(side ++ "_protocol", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = output,
        .imports = &.{
            .{ .name = "core", .module = core },
        },
    });
}

const protocols = .{
    .{ "stable/linux-dmabuf/linux-dmabuf-v1.xml", "zwp_linux_" },
    .{ "stable/presentation-time/presentation-time.xml", "wp_" },
    .{ "stable/tablet/tablet-v2.xml", "zwp_" },
    .{ "stable/viewporter/viewporter.xml", "wp_" },
    .{ "stable/xdg-shell/xdg-shell.xml", "xdg_" },

    .{ "staging/alpha-modifier/alpha-modifier-v1.xml", "wp_" },
    .{ "staging/color-management/color-management-v1.xml", "wp_" },
    .{ "staging/color-representation/color-representation-v1.xml", "wp_" },
    .{ "staging/commit-timing/commit-timing-v1.xml", "wp_" },
    .{ "staging/content-type/content-type-v1.xml", "wp_" },
    .{ "staging/cursor-shape/cursor-shape-v1.xml", "wp_" },
    .{ "staging/drm-lease/drm-lease-v1.xml", "wp_" },
    .{ "staging/ext-background-effect/ext-background-effect-v1.xml", "ext_" },
    .{ "staging/ext-data-control/ext-data-control-v1.xml", "ext_" },
    .{ "staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml", "ext_" },
    .{ "staging/ext-idle-notify/ext-idle-notify-v1.xml", "ext_" },
    .{ "staging/ext-image-capture-source/ext-image-capture-source-v1.xml", "ext_" },
    .{ "staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml", "ext_" },
    .{ "staging/ext-session-lock/ext-session-lock-v1.xml", "ext_" },
    .{ "staging/ext-transient-seat/ext-transient-seat-v1.xml", "ext_" },
    .{ "staging/ext-workspace/ext-workspace-v1.xml", "ext_" },
    .{ "staging/fifo/fifo-v1.xml", "wp_" },
    .{ "staging/fractional-scale/fractional-scale-v1.xml", "wp_" },
    .{ "staging/linux-drm-syncobj/linux-drm-syncobj-v1.xml", "wp_linux_" },
    .{ "staging/pointer-warp/pointer-warp-v1.xml", "wp_" },
    .{ "staging/security-context/security-context-v1.xml", "wp_" },
    .{ "staging/single-pixel-buffer/single-pixel-buffer-v1.xml", "wp_" },
    .{ "staging/tearing-control/tearing-control-v1.xml", "wp_" },
    .{ "staging/xdg-activation/xdg-activation-v1.xml", "xdg_" },
    .{ "staging/xdg-dialog/xdg-dialog-v1.xml", "xdg_" },
    .{ "staging/xdg-system-bell/xdg-system-bell-v1.xml", "xdg_" },
    .{ "staging/xdg-toplevel-drag/xdg-toplevel-drag-v1.xml", "xdg_" },
    .{ "staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml", "xdg_" },
    .{ "staging/xdg-toplevel-tag/xdg-toplevel-tag-v1.xml", "xdg_" },
    .{ "staging/xwayland-shell/xwayland-shell-v1.xml", "xwayland_" },

    .{ "unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml", "zwp_" },
    .{ "unstable/idle-inhibit/idle-inhibit-unstable-v1.xml", "zwp_" },
    .{ "unstable/input-method/input-method-unstable-v1.xml", "zwp_" },
    .{ "unstable/input-timestamps/input-timestamps-unstable-v1.xml", "zwp_" },
    .{ "unstable/keyboard-shortcuts-inhibit/keyboard-shortcuts-inhibit-unstable-v1.xml", "zwp_" },
    .{ "unstable/pointer-constraints/pointer-constraints-unstable-v1.xml", "zwp_" },
    .{ "unstable/pointer-gestures/pointer-gestures-unstable-v1.xml", "zwp_" },
    .{ "unstable/primary-selection/primary-selection-unstable-v1.xml", "zwp_" },
    .{ "unstable/relative-pointer/relative-pointer-unstable-v1.xml", "zwp_" },
    .{ "unstable/text-input/text-input-unstable-v3.xml", "zwp_" },
    .{ "unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", "zxdg_" },
    .{ "unstable/xdg-foreign/xdg-foreign-unstable-v2.xml", "zxdg_" },
    .{ "unstable/xdg-output/xdg-output-unstable-v1.xml", "zxdg_" },
    .{ "unstable/xwayland-keyboard-grab/xwayland-keyboard-grab-unstable-v1.xml", "zwp_xwayland_" },
};
