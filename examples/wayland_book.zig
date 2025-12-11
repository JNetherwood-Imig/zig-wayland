const std = @import("std");
const zwl = @import("zwl");
const wl = zwl.protocol.wayland;
const xdg = zwl.protocol.xdg_shell;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var id_buf: [16]u32 = undefined;
    var ida_state = zwl.FixedBufferIdAllocator.init(&id_buf);
    const ida = ida_state.allocator();

    var state = try State.init(gpa, ida);
    defer state.deinit(gpa);

    state.run(gpa) catch |err| {
        std.log.err("{t}.", .{err});
        state.getErrors();
        return err;
    };
}

const State = struct {
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

    const pixel_size = @sizeOf(u32);
    const pixel_format = wl.Shm.Format.xrgb8888;

    pub fn init(gpa: Allocator, ida: zwl.IdAllocator) !State {
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
                .wl_callback => |cb| std.debug.assert(cb.done.wl_callback == sync_callback),
                .wl_registry => |reg_ev| switch (reg_ev) {
                    .global => |glob| {
                        if (std.mem.eql(u8, glob.interface, wl.Compositor.interface)) {
                            compositor = try registry.bind(&conn, ida, wl.Compositor, .v6, glob.name);
                        } else if (std.mem.eql(u8, glob.interface, wl.Shm.interface)) {
                            shm = try registry.bind(&conn, ida, wl.Shm, .v1, glob.name);
                        } else if (std.mem.eql(u8, glob.interface, xdg.WmBase.interface)) {
                            shell = try registry.bind(&conn, ida, xdg.WmBase, .v6, glob.name);
                        }
                    },
                    .global_remove => continue,
                },
                else => std.log.warn("Unexpected event: {}.", .{ev}),
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

    pub fn run(self: *State, gpa: Allocator) !void {
        var close_callback: wl.Callback = @enumFromInt(0);
        var buf: [4096]u8 = undefined;
        while (self.handler.waitNextEvent(&self.conn, &buf)) |event| switch (event) {
            .xdg_wm_base => |ev| try self.shell.pong(&self.conn, ev.ping.serial),
            .xdg_surface => |ev| {
                try self.xdg_surface.ackConfigure(&self.conn, ev.configure.serial);

                if (self.data.len == 0)
                    try self.resize();

                try self.drawFrame();
            },
            .xdg_toplevel => |ev| switch (ev) {
                .configure => |config| {
                    if (config.width == 0 or config.height == 0) continue;

                    if (config.width != self.width or config.height != self.height) {
                        std.posix.munmap(self.data);
                        self.width = @intCast(config.width);
                        self.height = @intCast(config.height);
                        try self.resize();
                    }
                },
                .configure_bounds => |bounds| std.log.info(
                    "Toplevel has bounds {d}x{d}.",
                    .{ bounds.width, bounds.height },
                ),
                .wm_capabilities => |caps| {
                    const capabilities = std.mem.bytesAsSlice(u32, caps.capabilities);
                    for (capabilities) |cap|
                        std.log.info(
                            "Window manager supports {t}.",
                            .{@as(xdg.Toplevel.WmCapabilities, @enumFromInt(cap))},
                        );
                },
                .close => {
                    close_callback = try self.display.sync(&self.conn, self.ida);
                    try self.handler.addObject(gpa, close_callback);
                },
            },
            .wl_callback => |ev| {
                const cb = ev.done.wl_callback;
                if (cb == close_callback) break;

                // Assume surface frame callback
                // try self.handler.delObject(cb);
                // const new_cb = try self.surface.frame(&self.conn, self.ida);
                // try self.handler.addObject(gpa, new_cb);
                // std.log.debug("Frame.", .{});

                // try self.drawFrame();
            },
            .wl_buffer => |ev| {
                std.log.debug("Frame.", .{});
                try ev.release.wl_buffer.destroy(&self.conn);
                try self.handler.delObject(ev.release.wl_buffer);
            },
            .wl_shm => |ev| std.log.info("Shm has format {t}.", .{ev.format.format}),
            .wl_surface => |ev| switch (ev) {
                .enter => |enter| std.log.info(
                    "Surface gained focus on output {d}.",
                    .{@intFromEnum(enter.output)},
                ),
                .leave => |leave| std.log.info(
                    "Surface lost focus on output {d}.",
                    .{@intFromEnum(leave.output)},
                ),
                .preferred_buffer_scale => |scale| std.log.info(
                    "Surface preferred buffer scale is {d}.",
                    .{scale.factor},
                ),
                .preferred_buffer_transform => |transform| std.log.info(
                    "Surface preferred buffer transform is {t}.",
                    .{transform.transform},
                ),
            },
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
                    return error.ProtocolError;
                },
                .delete_id => |id| {
                    self.handler.delObject(id.id) catch {};
                    try self.ida.free(id.id);
                },
            },
            else => std.log.warn("Unhandled message: {}.", .{event}),
        } else |err| return err;
    }

    pub fn deinit(self: *State, gpa: Allocator) void {
        if (self.data.len > 0)
            std.posix.munmap(self.data);
        self.conn.close();
        self.handler.deinit(gpa);
    }

    pub fn getErrors(self: *State) void {
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
        const ts = try std.posix.clock_gettime(.REALTIME);
        var rand_state = std.Random.DefaultPrng.init(@intCast(ts.nsec));
        const rand = rand_state.random();
        var name: [8]u8 = undefined;
        name[0] = '/';
        name[7] = 0;
        for (1..6) |i| name[i] = @intCast((rand.int(i64) & 23) + 'A');

        const fd = std.c.shm_open(@ptrCast(&name), @bitCast(std.posix.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true }), 0o0600);
        _ = std.c.shm_unlink(@ptrCast(&name));
        _ = std.c.ftruncate(fd, @intCast(size));
        return fd;
    }
};
