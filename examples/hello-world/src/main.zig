const std = @import("std");
const wayland = @import("wayland");
const wl = @import("wl");
const xdg = @import("xdg_shell");

// Construct event type for protocols in use
const Event = wayland.Message(.{ wl, xdg });

const width = 256;
const height = 256;

// State variables
var configured: bool = false;
var conn: wayland.Connection = undefined;
const disp: wl.Display = .display; // wl_display has always has the special reserved id of 1.
var reg: wl.Registry = .invalid;
var comp: wl.Compositor = .invalid;
var shm: wl.Shm = .invalid;
var wm_base: xdg.WmBase = .invalid;
var surf: wl.Surface = .invalid;
var buffer: wl.Buffer = .invalid;
var shm_data: []align(4096) u8 = &.{};

pub fn main(args: std.process.Init) !void {
    const io = args.io;
    const env = args.environ_map;
    const gpa = args.gpa;

    const addr = try wayland.Address.default(env);
    conn = wayland.Connection.init(io, gpa, addr) catch |err| {
        std.log.err("Failed to connect to {f}: {t}.", .{ addr, err });
        return err;
    };
    defer conn.deinit();

    std.log.info("Connected to {f}.", .{addr});

    // Create registry
    reg = try disp.getRegistry(&conn);

    // Sync display to know when all registry globals have been received
    _ = try disp.sync(&conn);

    // Wait for all registry global events here to discover globals.
    // After the last global is sent, the server will send a `wl_callback.done` event
    // for `sync_cb`.
    while (conn.nextMessage(Event, .none)) |event| switch (event) {
        .wl_registry => |ev| switch (ev) {
            .global => |g| {
                // Bind to globals
                // Binding takes an enum for version which allows for
                // at least some comptime sanity-checking and less magic numbers
                if (std.mem.eql(u8, g.interface, wl.Compositor.interface)) {
                    comp = try reg.bind(&conn, wl.Compositor, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, wl.Shm.interface)) {
                    shm = try reg.bind(&conn, wl.Shm, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, xdg.WmBase.interface)) {
                    wm_base = try reg.bind(&conn, xdg.WmBase, .v1, g.name);
                }
            },
            .global_remove => {},
        },
        // All globals have been received, we can continue.
        .wl_callback => break,
        else => std.log.err("Unexpected event: {}.", .{event}),
    } else |e| return e;

    // Make sure we bound to all globals
    std.debug.assert(comp != .invalid and shm != .invalid and wm_base != .invalid);

    // Create and register wl_surface, xdg_surface, and xdg_toplevel
    surf = try comp.createSurface(&conn);
    const xdg_surf = try wm_base.getXdgSurface(&conn, surf);
    _ = try xdg_surf.getToplevel(&conn);

    // Perform initial surface commit to begin surface lifecycle.
    try surf.commit(&conn);

    // Main loop
    while (conn.nextMessage(Event, .none)) |event| switch (event) {
        .xdg_wm_base => |ev| try wm_base.pong(&conn, ev.ping.serial),
        .xdg_surface => |ev| {
            try xdg_surf.ackConfigure(&conn, ev.configure.serial);
            if (!configured) {
                // Create and register the buffer.
                try createBuffer();
                // Attach buffer to our surface so it can be presented.
                try surf.attach(&conn, buffer, 0, 0);
            }
            try surf.commit(&conn);
            configured = true;
        },
        // The only xdg toplevel event we care about is `close`.
        .xdg_toplevel => |ev| switch (ev) {
            .close => break,
            else => {},
        },
        .wl_display => |ev| switch (ev) {
            // There is no internal handling of the `wl_display.delete_id` event,
            // so an application should handle it here to allow the reuse of object ids.
            .delete_id => |id| try conn.releaseObject(id.id),
            // Much better handling of the error event could easily be done,
            // but it is unnecessary for the scope of this example.
            .@"error" => return error.ProtocolError,
        },
        else => {},
    } else |e| return e;

    // Begin cleanup by unmapping the shm buffer data.
    // The rest of cleanup will happen with defers.
    std.posix.munmap(shm_data);
}

// Create a wl_buffer backed by shm.
fn createBuffer() !void {
    const stride = width * 4;
    const size = stride * height;

    const fd = try allocateShmFile(size);
    defer std.posix.close(fd);

    shm_data = try std.posix.mmap(
        null,
        size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    // Fill buffer with white pixels.
    @memset(shm_data, 255);

    const pool = try shm.createPool(&conn, fd, size);
    defer pool.destroy(&conn) catch {};

    buffer = try pool.createBuffer(&conn, 0, width, height, stride, .argb8888);
}

// The following utility functions are quick and dirty replacements for the ones
// from wayland-book.com, written without shm_* functions because those are provided
// by libc and not available in zig std.os.linux or std.posix.

/// Allocate an shm file descriptor, truncated to `size` bytes.
fn allocateShmFile(size: usize) !i32 {
    const fd = try createShmFile();
    return switch (std.posix.errno(std.os.linux.ftruncate(fd, @intCast(size)))) {
        .SUCCESS => fd,
        else => |err| std.posix.unexpectedErrno(err),
    };
}

/// Create an shm file descriptor.
fn createShmFile() !i32 {
    const shm_prefix = "/dev/shm/wl_shm-";
    const shm_perms = 0o0600;
    const shm_opts: std.posix.O = .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .CLOEXEC = true,
        .EXCL = true,
        .NOFOLLOW = true,
    };

    var path: [22:0]u8 = @splat(0);
    @memcpy(path[0..shm_prefix.len], shm_prefix);

    const fd: i32 = while (true) {
        try randomize(path[shm_prefix.len..]);
        const rc = std.os.linux.open(&path, shm_opts, shm_perms);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break @intCast(rc),
            else => continue,
        }
    };

    _ = std.os.linux.unlink(&path);
    return fd;
}

/// Fill `buf` with random characters.
fn randomize(buf: []u8) !void {
    const ts = try std.posix.clock_gettime(.REALTIME);
    var r = ts.nsec;
    for (buf) |*byte| {
        byte.* = 'A' + @as(u8, @intCast((r & 15) + (r & 16) * 2));
        r >>= 5;
    }
}
