const std = @import("std");
const wayland = @import("wayland");
const protocol = @import("protocol");
const wl = protocol.wayland;
const xdg = protocol.xdg_shell;
// Construct event handler type for default protocols
const EventHandler = wayland.EventHandler(protocol);

const width = 256;
const height = 256;

// State variables
var configured: bool = false;
var conn: wayland.Connection = undefined;
var disp = wl.Display.null_handle;
var reg = wl.Registry.null_handle;
var comp = wl.Compositor.null_handle;
var shm = wl.Shm.null_handle;
var wm_base = xdg.WmBase.null_handle;
var shm_data: []align(4096) u8 = &.{};
var surf = wl.Surface.null_handle;

pub fn main() !void {
    // Create ID allocator backed by small buffer
    var id_buf: [16]u32 = undefined;
    var ida_state = wayland.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.id_allocator();

    // Shortcut for creating stack buffers used by connection
    var buffers = wayland.Connection.Buffers{};
    // Create connection using buffers
    conn = try wayland.getConnectInfo().connect(ida, &buffers);

    // Create event handler backed by stack buffer
    var proxy_buf: [16]EventHandler.Proxy = undefined;
    var handler = EventHandler.initBuffered(&proxy_buf);

    // Create display to bootstrap object creation
    disp = try ida.createObject(wl.Display);
    // Register display with event handler to receive events
    try handler.addObjectBounded(disp);

    // Create and register registry
    reg = try disp.getRegistry(&conn);
    try handler.addObjectBounded(reg);

    // Sync display to know when all registry globals have been received
    const sync_cb = try disp.sync(&conn);
    try handler.addObjectBounded(sync_cb);

    while (handler.waitNextEvent(&conn)) |event| switch (event) {
        .wl_callback => break, // Indicates that all globals have been received
        .wl_registry => |ev| switch (ev) {
            .global => |g| {
                // Bind to globals
                // Binding takes an enum for version which allows for
                // at least some comptime sanity-checking and less magic numbers
                if (std.mem.eql(u8, g.interface, wl.Compositor.interface)) {
                    // We don't care about any compositor events here,
                    // so there is no reason to add it to the event handler
                    comp = try reg.bind(&conn, wl.Compositor, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, wl.Shm.interface)) {
                    // Shm events can also be discarded
                    shm = try reg.bind(&conn, wl.Shm, .v1, g.name);
                } else if (std.mem.eql(u8, g.interface, xdg.WmBase.interface)) {
                    wm_base = try reg.bind(&conn, xdg.WmBase, .v1, g.name);
                    try handler.addObjectBounded(wm_base);
                }
            },
            else => {},
        },
        else => std.log.err("Unexpected event: {any}.", .{event}),
    } else |e| return e;
    // Make sure we bound to all globals by comparing to null_handle type that each interface has
    std.debug.assert(comp != .null_handle and shm != .null_handle and wm_base != .null_handle);

    // Create and register wl_surface, xdg_surface, and xdg_toplevel
    surf = try comp.createSurface(&conn);
    try handler.addObjectBounded(surf);
    const xdg_surf = try wm_base.getXdgSurface(&conn, surf);
    try handler.addObjectBounded(xdg_surf);
    const toplevel = try xdg_surf.getToplevel(&conn);
    try handler.addObjectBounded(toplevel);

    try surf.commit(&conn);

    // Main loop
    while (handler.waitNextEvent(&conn)) |event| switch (event) {
        .xdg_wm_base => |ev| try wm_base.pong(&conn, ev.ping.serial),
        .xdg_surface => |ev| {
            try xdg_surf.ackConfigure(&conn, ev.configure.serial);
            if (!configured) {
                const buffer = try createBuffer();
                try surf.attach(&conn, buffer, 0, 0);
            }
            try surf.commit(&conn);
        },
        .xdg_toplevel => |ev| switch (ev) {
            .close => break,
            else => {},
        },
        .wl_display => |ev| switch (ev) {
            .@"error" => return error.ProtocolError,
            .delete_id => |id| {
                // IMPORTANT: Object IDs are not automatically freed,
                // since the wl_display.delete_id event is not handled internally.
                // Thus, the server will immediately terminate the client connection
                // if IDs are not correctly freed
                handler.delObject(id.id);
                try ida.free(id.id);
            },
        },
        else => {},
    } else |e| return e;

    if (shm_data.len > 0) std.posix.munmap(shm_data);
}

fn createBuffer() !wl.Buffer {
    const stride = width * 4;
    const size = stride * height;

    const fd = try allocateShmFile(size);
    defer std.posix.close(fd);

    shm_data = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    // Neither the pool nor the buffer need to be registered with the event handler
    // because we don't care about their events.
    const pool = try shm.createPool(&conn, fd, size);
    defer pool.destroy(&conn) catch {};
    const buffer = try pool.createBuffer(&conn, 0, width, height, stride, .argb8888);

    @memset(shm_data, 255);

    // IMPORTANT: the connection must be flushed before the fd is closed
    // because the fd is not duplicated when being stored in the connection buffer,
    // and must be sent before it is closed.
    try conn.flush();

    return buffer;
}

// The following utility functions are quick and dirty replacements
// for the ones from wayland-book.com, written without shm* functions
// because those are provided by libc.

fn allocateShmFile(size: usize) !std.posix.fd_t {
    const fd = try createShmFile();
    try std.posix.ftruncate(fd, size);
    return fd;
}

fn createShmFile() !std.posix.fd_t {
    while (true) {
        var path: [22:0]u8 = @splat(0);
        @memcpy(path[0..16], "/dev/shm/wl_shm-");
        try randomize(path[path.len - 6 ..]);
        const fd = std.posix.open(
            &path,
            .{
                .ACCMODE = .RDWR,
                .CREAT = true,
                .CLOEXEC = true,
                .EXCL = true,
                .NOFOLLOW = true,
            },
            0o0600,
        ) catch continue;
        try std.posix.unlink(&path);
        return fd;
    }
}

fn randomize(buf: []u8) !void {
    const ts = try std.posix.clock_gettime(.REALTIME);
    var r = ts.nsec;
    for (0..buf.len) |i| {
        buf[i] = 'A' + @as(u8, @intCast((r & 15) + (r & 16) * 2));
        r >>= 5;
    }
}
