const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wayland = b.dependency("wayland", .{});
    const zwl = wayland.module("client");
    // const vulkan_headers = b.dependency("vulkan_headers", .{});
    // const vulkan = b.dependency("vulkan", .{
    //     .registry = vulkan_headers.path("registry/vk.xml"),
    // });

    const wayland_book = b.addExecutable(.{
        .name = "wayland-book",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("wayland-book/main.zig"),
        }),
    });
    wayland_book.root_module.addImport("zwl", zwl);
    b.installArtifact(wayland_book);
    const run_wayland_book = b.addRunArtifact(wayland_book);
    const run_wayland_book_step = b.step("run-wayland-book", "Run wayland book example.");
    run_wayland_book_step.dependOn(&run_wayland_book.step);

    // const hello_triangle = b.addExecutable(.{
    //     .name = "hello-triangle",
    //     .root_module = b.createModule(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .root_source_file = b.path("vulkan-hello-triangle/main.zig"),
    //         .link_libc = true,
    //     }),
    // });
    // hello_triangle.root_module.addImport("zwl", zwl);
    // hello_triangle.root_module.addImport("vulkan", vulkan.module("vulkan-zig"));
    // hello_triangle.root_module.linkSystemLibrary("dl", .{});
    // b.installArtifact(hello_triangle);
    // const run_hello_triangle = b.addRunArtifact(hello_triangle);
    // const run_hello_triangle_step = b.step("run-hello-triangle", "Run Vulkan hello triangle example.");
    // run_hello_triangle_step.dependOn(&run_hello_triangle.step);
}
