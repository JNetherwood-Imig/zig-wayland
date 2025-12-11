const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;
const xdg = zwl.protocol.xdg_shell;
const Allocator = std.mem.Allocator;
const pixel_size = @sizeOf(u32);
const pixel_format = wl.Shm.Format.xrgb8888;
const State = @This();

conn: zwl.Connection,
ida: zwl.IdAllocator,
handler: zwl.EventHandler,

display: wl.Display,
registry: wl.Registry,
compositor: wl.Compositor,
shm: wl.Shm,
shell: xdg.WmBase,

surface: wl.Surface,
xdg_surface: xdg.Surface,
toplevel: xdg.Toplevel,

buffer: wl.Buffer,
data: []align(4096) u8,

width: u32,
height: u32,

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var id_buf: [16]u32 = undefined;
    var ida_state = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.allocator();

    var state = try init(gpa, ida);
    defer state.deinit(gpa);

    state.run(gpa) catch |err| {
        std.log.err("{t}.", .{err});
        state.getErrors();
        return err;
    };
}

fn init(gpa: Allocator, ida: zwl.IdAllocator) !State {
    const conn_info = zwl.getConnectInfo();
    var conn = conn_info.connect() catch |err| {
        std.log.err("Failed to connect to wayland server: {t} ({f}).", .{ err, conn_info });
        return err;
    };
    errdefer conn.close();

    var handler = try zwl.EventHandler.init(gpa);
    errdefer handler.deinit(gpa);

    const display = try ida.create(wl.Display);
    try handler.addObject(gpa, display);
    const registry = try display.getRegistry(&conn, ida);
    try handler.addObject(gpa, registry);

    const compositor, const shm, const shell = blk: {
        var buf: [4096]u8 = undefined;
        const sync_callback = try display.sync(&conn, ida);
        try handler.addObject(gpa, sync_callback);
        var compositor: ?wl.Compositor = null;
        var shm: ?wl.Shm = null;
        var shell: ?xdg.WmBase = null;
        while (handler.waitNextEvent(&conn, &buf)) |ev| switch (ev) {
            .wl_display => |disp| switch (disp) {
                .@"error" => return error.ProtocolError,
                .delete_id => |id| {
                    try handler.delObject(id.id);
                    try ida.free(id.id);
                    if (id.id == sync_callback.getId()) break;
                },
            },
            .wl_registry => |reg_ev| switch (reg_ev) {
                .global => |glob| {
                    if (std.mem.eql(u8, glob.interface, wl.Compositor.interface))
                        compositor = try registry.bind(&conn, ida, wl.Compositor, .v6, glob.name)
                    else if (std.mem.eql(u8, glob.interface, wl.Shm.interface))
                        shm = try registry.bind(&conn, ida, wl.Shm, .v1, glob.name)
                    else if (std.mem.eql(u8, glob.interface, xdg.WmBase.interface))
                        shell = try registry.bind(&conn, ida, xdg.WmBase, .v6, glob.name);
                },
                else => {},
            },
            else => {},
        } else |err| return err;

        break :blk .{
            compositor orelse return error.NoCompositor,
            shm orelse return error.NoShm,
            shell orelse return error.NoXdgShell,
        };
    };

    try handler.addObject(gpa, compositor);
    try handler.addObject(gpa, shm);
    try handler.addObject(gpa, shell);

    const surface = try compositor.createSurface(&conn, ida);
    const frame_cb = try surface.frame(&conn, ida);
    const xdg_surface = try shell.getXdgSurface(&conn, ida, surface);
    const toplevel = try xdg_surface.getToplevel(&conn, ida);
    try toplevel.setTitle(&conn, "Zig Wayland Book Example");
    try surface.commit(&conn);

    try handler.addObject(gpa, surface);
    try handler.addObject(gpa, frame_cb);
    try handler.addObject(gpa, xdg_surface);
    try handler.addObject(gpa, toplevel);

    return State{
        .conn = conn,
        .ida = ida,
        .handler = handler,
        .display = display,
        .registry = registry,
        .compositor = compositor,
        .shm = shm,
        .shell = shell,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .toplevel = toplevel,
        .buffer = @enumFromInt(0),
        .data = &.{},
        .width = 1280,
        .height = 720,
    };
}

fn run(self: *State, gpa: Allocator) !void {
    var close_callback: wl.Callback = @enumFromInt(0);
    var buf: [4096]u8 = undefined;
    while (self.handler.waitNextEvent(&self.conn, &buf)) |event| switch (event) {
        .xdg_wm_base => |ev| try self.shell.pong(&self.conn, ev.ping.serial),
        .xdg_surface => |ev| {
            try self.xdg_surface.ackConfigure(&self.conn, ev.configure.serial);

            if (self.data.len == 0) try self.resize();
            try self.drawFrame();
        },
        .xdg_toplevel => |ev| switch (ev) {
            .configure => |config| {
                if (config.width == 0 or config.height == 0) continue;

                if (config.width != self.width or config.height != self.height) {
                    if (self.data.len > 0) std.posix.munmap(self.data);
                    self.width = @intCast(config.width);
                    self.height = @intCast(config.height);
                    try self.resize();
                }
            },
            .close => {
                close_callback = try self.display.sync(&self.conn, self.ida);
                try self.handler.addObject(gpa, close_callback);
            },
            else => {},
        },
        .wl_callback => |ev| {
            const cb = ev.done.wl_callback;
            if (cb == close_callback) break;

            // Assume surface frame callback
            try self.handler.delObject(cb);
            const new_cb = try self.surface.frame(&self.conn, self.ida);
            try self.handler.addObject(gpa, new_cb);

            try self.drawFrame();
        },
        .wl_buffer => |ev| {
            try ev.release.wl_buffer.destroy(&self.conn);
            try self.handler.delObject(ev.release.wl_buffer);
        },
        .wl_display => |ev| switch (ev) {
            .@"error" => return error.ProtocolError,
            .delete_id => |id| {
                self.handler.delObject(id.id) catch {};
                try self.ida.free(id.id);
            },
        },
        else => {},
    } else |err| return err;
}

fn deinit(self: *State, gpa: Allocator) void {
    if (self.data.len > 0)
        std.posix.munmap(self.data);
    self.conn.close();
    self.handler.deinit(gpa);
}

fn getErrors(self: *State) void {
    var buf: [4096]u8 = undefined;
    while (self.handler.waitNextEvent(&self.conn, &buf)) |event| switch (event) {
        .wl_display => |ev| switch (ev) {
            .@"error" => |e| {
                const interface = for (self.handler.proxies.items) |p| {
                    if (p.id == e.object_id) break p.interface;
                } else "unknown";
                std.log.err("Protocol error: object {s}#{d}: code {d}: {s}.", .{
                    interface,
                    e.object_id,
                    e.code,
                    e.message,
                });
                return;
            },
            .delete_id => |id| self.handler.delObject(id.id) catch {},
        },
        else => {},
    } else |_| {}
}

fn resize(self: *State) !void {
    const fd = try allocateShmFile(self.width * self.height * pixel_size);
    defer std.posix.close(fd);

    self.data = try std.posix.mmap(
        null,
        self.width * self.height * pixel_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    const pool = try self.shm.createPool(
        &self.conn,
        self.ida,
        fd,
        @intCast(self.width * self.height * pixel_size),
    );
    defer pool.destroy(&self.conn) catch {};

    self.buffer = try pool.createBuffer(
        &self.conn,
        self.ida,
        0,
        @intCast(self.width),
        @intCast(self.height),
        @intCast(self.width * pixel_size),
        pixel_format,
    );
}

fn drawFrame(self: *State) !void {
    const pixels = std.mem.bytesAsSlice(u32, self.data);

    for (0..self.height) |y| {
        for (0..self.width) |x| {
            pixels[y * self.width + x] = if ((x + y / 8 * 8) % 16 < 8)
                0xFF666666
            else
                0xFFEEEEEE;
        }
    }

    try self.surface.attach(&self.conn, self.buffer, 0, 0);
    try self.surface.damageBuffer(&self.conn, 0, 0, @intCast(self.width), @intCast(self.height));
    try self.surface.commit(&self.conn);
}

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
