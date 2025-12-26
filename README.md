# Zig Wayland

A pure zig implementation of the Wayland protocol for creating both client and server applications.

## Installation

Can be used as a dependency of any zig 0.15 project.

To use latest release, run
```sh
zig fetch --save https://codeberg.org/jacksonni/zig-wayland/archive/v1.0.2.tar.gz
```

Or to use master branch, run
```sh
zig fetch --save git+https://codeberg.org/jacksonni/zig-wayland
```

## Documentation

Official API documentation is hosted at
[jacksonni.codeberg.page/zig-wayland](https://jacksonni.codeberg.page/zig-wayland).

## Examples

For full example programs, refer to the examples directory.

### Usage
```zig
// build.zig
const std = @import("std");
pub fn build(b: *std.Build) void {
    const wayland_dep = b.dependency("wayland", .{});
    
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("main.zig"),
        }),
    });
    exe.root_module.addImport("wayland", wayland_dep.module("wayland_core"));
    exe.root_module.addImport("wl", wayland_dep.module("wayland_client_protocol"));
    exe.root_module.addImport("xdg_shell", wayland_dep.module("xdg_shell_client_protocol"));
    b.installArtifact(exe);
}

// main.zig
const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wl");
const xdg_shell = @import("xdg_shell");

pub fn main() !void {...}
```

### Custom protocols

The ability to generate code for any protocol is a key feature of a fully extensible API. This is achieved here with the provided scanner program and `generateDependencyInfo` and `generateProtocol` functions from build.zig.

The `generateDependencyInfo` function takes a path to xml, prefix to strip from interfaces, and output file name. It will write the names of the types that would be generated for the xml to the output file. It returns a LazyPath which can be used in the `imports` parameter of `generateProtocol`.

The `generateProtocol` function takes a path to xml, prefix to strip from iterfaces, an output file name, a list of imports, and a protocol side to generate code for.

Dependency information for packaged protocols can be accessed via a named lazy path "{protocol name}_dep".

```zig
// The following code would be for generating client code for hyprland-surface-v1.xml.
// build.zig
const std = @import("std");
const wayland = @import("wayland");
pub fn build(b: *std.Build) void {
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_core = wayland_dep.module("wayland_core");
    const wayland_scanner = wayland_dep.artifact("wayland_scanner");
    const wayland_client_protocol = wayland_dep.module("wayland_client_protocol");
    // Get dependency information for wayland protocol which is needed by hyprland-surface-v1 for wl_surface.
    const wayland_protocol_dep_info = wayland_dep.namedLazyPath("wayland_dep");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hyprland_surface_v1_code = wayland.generateProtocol(
        b,
        wayland_scanner,
        b.path("hyprland-surface-v1.xml"), // Path to source xml
        "hyprland", // Prefix to strip from interface names, "" to disable stripping.
        "hyprland_surface_v1.zig", // Basename of output file, can be anything
        &.{wayland_protocol_dep_info}, // Slice of .dep files providing foreign interfaces (wl_surface in this case).
        .client,
    );
    
    const hyprland_surface_v1 = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = hyprland_surface_v1_code,
    });
    
    // wayland_core **must** be imported as "core".
    hyprland_surface_v1.addImport("core", wayland_core);
    // hyprland-surface-v1 depends on wl_surface, so "wayland" must also be imported.
    hyprland_surface_v1.addImport("wayland", wayland_client_protocol);

    const exe = b.addExecutable(...);
    exe.root_module.addImport("wayland", wayland_core);
    exe.root_module.addImport("wayland_protocol", wayland_client_protocol);
    // Use hyprland_surface_v1 as you would any other protocol.
    exe.root_module.addImport("hyprland_surface", hyprland_surface_v1);
    b.installArtifact(exe);
}
```

## SAFETY WARNING

### If your Wayland client NEVER spawns a child process, or no child process has any chance of spawning its own child Wayland process, then you can safely ignore this warning.

There are two conventional ways for a Wayland client to connect to the server. The standard way uses the WAYLAND_DISPLAY environment variable. The other way uses the WAYLAND_SOCKET environment variable. A parent Wayland client will set this and the child process will interpret it as an open file descriptor. This works fine with the libc/posix model for environment variables, but not with the zig approach.

There a few ways to work around this:
* Link libc
  - When the resulting executable is linked with libc, the WAYLAND_SOCKET environment variable will be unset just as libwayland does, and there will be no issues.
* Unset when spawning
  - If you don't want to link libc, then all you have to do is spawn any child processes using execve and make sure that WAYLAND_SOCKET has been removed from the given env map.
