const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/core.zig"),
    });

    const client = b.addModule("client", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
    });
    client.addImport("core", core);

    const server = b.addModule("server", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });
    server.addImport("core", core);

    addProtocols(b, target, optimize, core);

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

fn addProtocols(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
) void {
    const core_dep = b.dependency("wayland", .{});
    const protocols_dep = b.dependency("wayland_protocols", .{});
    const scanner = makeScanner(b, target, optimize);
    inline for (.{ "client", "server" }) |mode| {
        const run_scanner = b.addRunArtifact(scanner);
        run_scanner.addArgs(&.{ "-m", mode });
        run_scanner.addArg("-o");
        const output_file = run_scanner.addOutputFileArg(mode ++ "-" ++ "protocol" ++ ".zig");
        run_scanner.addArgs(&.{ "-p", "wl_" });
        run_scanner.addFileArg(core_dep.path("protocol/wayland.xml"));
        for (wayland_protocols_paths) |protocol| {
            run_scanner.addArgs(&.{ "-p", protocol.prefix });
            run_scanner.addFileArg(protocols_dep.path(protocol.path));
        }
        const mod = b.addModule(mode ++ "-" ++ "protocol", .{
            .target = target,
            .optimize = optimize,
            .root_source_file = output_file,
        });
        mod.addImport("core", core);
    }
}

const ProtocolInfo = struct {
    path: []const u8,
    prefix: []const u8,
};

const wayland_protocols_paths = [_]ProtocolInfo{
    .{ .path = "stable/linux-dmabuf/linux-dmabuf-v1.xml", .prefix = "zwp_linux_" },
    .{ .path = "stable/presentation-time/presentation-time.xml", .prefix = "wp_" },
    .{ .path = "stable/tablet/tablet-v2.xml", .prefix = "zwp_" },
    .{ .path = "stable/viewporter/viewporter.xml", .prefix = "wp_" },
    .{ .path = "stable/xdg-shell/xdg-shell.xml", .prefix = "xdg_" },

    .{ .path = "staging/alpha-modifier/alpha-modifier-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/color-management/color-management-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/color-representation/color-representation-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/commit-timing/commit-timing-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/content-type/content-type-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/cursor-shape/cursor-shape-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/drm-lease/drm-lease-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/ext-background-effect/ext-background-effect-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-data-control/ext-data-control-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-idle-notify/ext-idle-notify-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-image-capture-source/ext-image-capture-source-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-session-lock/ext-session-lock-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-transient-seat/ext-transient-seat-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/ext-workspace/ext-workspace-v1.xml", .prefix = "ext_" },
    .{ .path = "staging/fifo/fifo-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/fractional-scale/fractional-scale-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/linux-drm-syncobj/linux-drm-syncobj-v1.xml", .prefix = "wp_linux_" },
    .{ .path = "staging/pointer-warp/pointer-warp-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/security-context/security-context-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/single-pixel-buffer/single-pixel-buffer-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/tearing-control/tearing-control-v1.xml", .prefix = "wp_" },
    .{ .path = "staging/xdg-activation/xdg-activation-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xdg-dialog/xdg-dialog-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xdg-system-bell/xdg-system-bell-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xdg-toplevel-drag/xdg-toplevel-drag-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xdg-toplevel-tag/xdg-toplevel-tag-v1.xml", .prefix = "xdg_" },
    .{ .path = "staging/xwayland-shell/xwayland-shell-v1.xml", .prefix = "xwayland_" },

    .{ .path = "unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/idle-inhibit/idle-inhibit-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/input-method/input-method-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/input-timestamps/input-timestamps-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/keyboard-shortcuts-inhibit/keyboard-shortcuts-inhibit-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/pointer-constraints/pointer-constraints-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/pointer-gestures/pointer-gestures-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/primary-selection/primary-selection-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/relative-pointer/relative-pointer-unstable-v1.xml", .prefix = "zwp_" },
    .{ .path = "unstable/text-input/text-input-unstable-v3.xml", .prefix = "zwp_" },
    .{ .path = "unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", .prefix = "zxdg_" },
    .{ .path = "unstable/xdg-foreign/xdg-foreign-unstable-v2.xml", .prefix = "zxdg_" },
    .{ .path = "unstable/xdg-output/xdg-output-unstable-v1.xml", .prefix = "zxdg_" },
    .{ .path = "unstable/xwayland-keyboard-grab/xwayland-keyboard-grab-unstable-v1.xml", .prefix = "zwp_xwayland_" },
};
