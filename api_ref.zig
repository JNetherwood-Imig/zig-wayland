const zwl = struct {
    const std = @import("std");
    pub const Connection = struct {
        socket: i32,
        proxies: std.ArrayList(Proxy),

        pub fn validateRequest(
            self: Connection,
            id: u32,
            deprecated_since: ?u32,
            since: u32,
        ) !void {
            for (self.proxies.items) |proxy| {
                if (proxy.id == id) {
                    if (proxy.version < since)
                        return error.InvalidRequest;
                    if (deprecated_since) |ds| if (proxy.version > ds)
                        return error.Deprecated;
                }
            }
        }
    };
    pub const IdAllocator = struct {
        next_id: u32,
        pub fn alloc(self: *IdAllocator) !u32 {
            return self.next_id;
        }
    };
    const Proxy = struct {
        id: u32,
        version: u32,
        interface: []const u8,
    };
};

pub const protocol = struct {
    pub const wayland = struct {
        pub const Display = enum(u32) {
            _,

            pub const interface = "wl_display";
            pub const Version = enum { v1 };

            pub fn sync(
                self: Display,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
            ) !Callback {
                _ = self;
                _ = connection;
                return @enumFromInt(try ida.alloc());
            }

            pub fn getRegistry(
                self: Display,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
            ) !Registry {
                _ = self;
                _ = connection;
                return @enumFromInt(try ida.alloc());
            }

            pub const ErrorEvent = struct {
                object_id: u32,
                code: u32,
                message: []const u8,
            };

            pub const DeleteIdEvent = struct {
                id: u32,
            };

            const Events = .{
                ErrorEvent,
                DeleteIdEvent,
            };

            pub const Error = enum(i32) {
                invalid_object = 0,
                invalid_method = 1,
                no_memory = 2,
                implementation = 3,
                fn toError(self: Error) anyerror {
                    return switch (self) {
                        .invalid_object => error.DisplayErrorInvalidObject,
                        .invalid_method => error.DisplayErrorInvalidMethod,
                        .no_memory => error.DisplayErrorNoMemory,
                        .implementation => error.DisplayErrorImplementation,
                    };
                }
            };
        };

        pub const Registry = enum(u32) {
            _,

            pub const interface = "wl_registry";
            pub const Version = enum { v1 };

            pub fn bind(
                self: Registry,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
                comptime Interface: type,
                version: Interface.Version,
                name: u32,
            ) !Interface {
                _ = self;
                _ = connection;
                _ = name;
                _ = version;
                return @enumFromInt(try ida.alloc());
            }

            pub const GlobalEvent = struct {
                self: Registry,
                name: u32,
                interface: []const u8,
                version: u32,
            };

            pub const GlobalRemoveEvent = struct {
                self: Registry,
                name: u32,
            };

            const Events = .{
                GlobalEvent,
                GlobalRemoveEvent,
            };
        };

        pub const Compositor = enum(u32) {
            _,

            pub const interface = "wl_compositor";
            pub const Version = enum {
                v1,
                v2,
                v3,
                v4,
                v5,
                v6,
            };

            pub fn createSurface(
                self: Compositor,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
            ) !Surface {
                _ = self;
                _ = connection;
                return @enumFromInt(try ida.alloc());
            }
            pub fn createRegion(
                self: Compositor,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
            ) !Region {
                _ = self;
                _ = connection;
                return @enumFromInt(try ida.alloc());
            }
        };

        pub const Surface = enum(u32) {
            _,

            pub const interface = "wl_surface";
            pub const Version = enum {
                v1,
                v2,
                v3,
                v4,
                v5,
                v6,
            };

            pub fn destroy(
                self: Surface,
                connection: zwl.Connection,
            ) !void {
                _ = self;
                _ = connection;
            }

            pub fn attach(
                self: Surface,
                connection: zwl.Connection,
                buffer: Buffer,
            ) !void {
                _ = self;
                _ = connection;
                _ = buffer;
            }

            pub fn damage(
                self: Surface,
                connection: zwl.Connection,
                x: i32,
                y: i32,
                width: i32,
                height: i32,
            ) !void {
                _ = self;
                _ = connection;
                _ = x;
                _ = y;
                _ = width;
                _ = height;
            }

            pub fn frame(
                self: Surface,
                connection: zwl.Connection,
                ida: *zwl.IdAllocator,
            ) !Callback {
                _ = self;
                _ = connection;
                return @enumFromInt(try ida.alloc());
            }
            pub fn setOpaqueRegion(
                self: Surface,
                connection: zwl.Connection,
                region: ?Region,
            ) !void {
                _ = self;
                _ = connection;
                _ = region;
            }
            pub fn setInputRegion(
                self: Surface,
                connection: zwl.Connection,
                region: ?Region,
            ) !void {
                _ = self;
                _ = connection;
                _ = region;
            }
            pub fn commit(
                self: Surface,
                connection: zwl.Connection,
            ) !void {
                _ = self;
                _ = connection;
            }
            pub fn setBufferTransform(
                self: Surface,
                connection: zwl.Connection,
                transform: Output.Transform,
            ) !void {
                _ = self;
                _ = connection;
                _ = transform;
            }
            pub fn setBufferScale(
                self: Surface,
                connection: zwl.Connection,
                scale: i32,
            ) !void {
                _ = self;
                _ = connection;
                _ = scale;
            }
            pub fn damageBuffer(
                self: Surface,
                connection: zwl.Connection,
                x: i32,
                y: i32,
                width: i32,
                height: i32,
            ) !void {
                _ = self;
                _ = connection;
                _ = x;
                _ = y;
                _ = width;
                _ = height;
            }
            pub fn offset(
                self: Surface,
                connection: zwl.Connection,
                x: i32,
                y: i32,
            ) !void {
                _ = self;
                _ = connection;
                _ = x;
                _ = y;
            }

            pub const EnterEvent = struct {
                self: Surface,
                output: Output,
            };

            pub const LeaveEvent = struct {
                self: Surface,
                output: Output,
            };

            pub const PreferredBufferScaleEvent = struct {
                factor: i32,
            };

            pub const PreferredBufferTransformEvent = struct {
                self: Surface,
                transform: Output.Transform,
            };

            const Events = .{
                EnterEvent,
                LeaveEvent,
                PreferredBufferScaleEvent,
                PreferredBufferTransformEvent,
            };

            pub const Error = enum(i32) {
                invalid_scale = 0,
                invalid_transform = 1,
                invalid_size = 2,
                invalid_offset = 3,
                defunct_role_object = 4,
            };
        };

        pub const Region = enum(u32) {
            _,

            pub const interface = "wl_region";
            pub const Version = enum {
                v1,
            };

            pub fn destroy(
                self: Region,
            ) !void {
                _ = self;
            }
            pub fn add(
                self: Region,
                x: i32,
                y: i32,
                width: i32,
                height: i32,
            ) !void {
                _ = self;
                _ = x;
                _ = y;
                _ = width;
                _ = height;
            }
            pub fn subtract(
                self: Region,
                x: i32,
                y: i32,
                width: i32,
                height: i32,
            ) !void {
                _ = self;
                _ = x;
                _ = y;
                _ = width;
                _ = height;
            }
        };

        pub const Output = enum(u32) {
            _,

            pub const interface = "wl_output";
            pub const Version = enum { v1, v2, v3, v4 };

            pub fn release(
                self: Output,
            ) !void {
                _ = self;
            }

            pub const GeometryEvent = struct {
                self: Output,
                x: i32,
                y: i32,
                physical_width: i32,
                physical_height: i32,
                subpixel: Subpixel,
                make: []const u8,
                model: []const u8,
                transform: Transform,
            };
            pub const ModeEvent = struct {
                self: Output,
                flags: Mode,
                width: i32,
                height: i32,
                refresh: i32,
            };
            pub const DoneEvent = struct {
                self: Output,
            };
            pub const ScaleEvent = struct {
                self: Output,
                scale: i32,
            };
            pub const NameEvent = struct {
                self: Output,
                name: []const u8,
            };
            pub const DescriptionEvent = struct {
                self: Output,
                description: []const u8,
            };
            const Events = .{
                GeometryEvent,
                ModeEvent,
                DoneEvent,
                ScaleEvent,
                NameEvent,
                DescriptionEvent,
            };

            pub const Subpixel = enum(i32) {
                unknown,
                none,
                horizontal_rgb,
                horizontal_bgr,
                vertical_rgb,
                vertical_bgr,
            };

            pub const Transform = enum(i32) {
                normal = 0,
                @"90" = 1,
                @"180" = 2,
                @"270" = 3,
                flipped = 4,
                flipped_90 = 5,
                flipped_180 = 6,
                flipped_270 = 7,
            };

            pub const Mode = packed struct(u32) {
                current: bool = false,
                preferred: bool = false,
                _: u30 = 0,
            };
        };
        const Callback = enum(u32) {};
        const Buffer = enum(u32) {};
    };
};

const client_test = struct {
    const wl = protocol.wayland;
    const State = struct {
        conn: zwl.Connection,
        ida: zwl.IdAllocator,
        display: wl.Display,
        registry: wl.Registry,
        compositor: wl.Compositor,
        surface: wl.Surface,
        outputs: @import("std").ArrayList(wl.Output),

        pub fn init() State {
            const conn: zwl.Connection = undefined;
            const ida: zwl.IdAllocator = undefined;
            const display: wl.Display = undefined;
            const registry = try display.getRegistry(conn, &ida);
            const compositor = try registry.bind(conn, &ida, wl.Compositor, .v6, 1);
            const surface = try compositor.createSurface(conn, &ida);
            surface.destroy(conn);
        }
    };
};
