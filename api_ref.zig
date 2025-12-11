pub const protocol = struct {
    pub const wayland = struct {
        pub const Display = enum(u32) {
            _,

            pub const interface = "wl_display";
            pub const Version = enum { v1 };

            pub fn sync(
                self: Display,
            ) !Callback {
                _ = self;
            }
            pub fn getRegistry(
                self: Display,
            ) !Registry {
                _ = self;
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
                comptime Interface: type,
                version: Interface.Version,
                name: u32,
            ) !Interface {
                _ = self;
                _ = name;
                _ = version;
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
            ) !Surface {
                _ = self;
            }
            pub fn createRegion(
                self: Compositor,
            ) !Region {
                _ = self;
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
            ) !void {
                _ = self;
            }
            pub fn attach(
                self: Surface,
                buffer: Buffer,
            ) !void {
                _ = self;
                _ = buffer;
            }
            pub fn damage(
                self: Surface,
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
            pub fn frame(
                self: Surface,
            ) !Callback {
                _ = self;
            }
            pub fn setOpaqueRegion(
                self: Surface,
                region: ?Region,
            ) !void {
                _ = self;
                _ = region;
            }
            pub fn setInputRegion(
                self: Surface,
                region: ?Region,
            ) !void {
                _ = self;
                _ = region;
            }
            pub fn commit(
                self: Surface,
            ) !void {
                _ = self;
            }
            pub fn setBufferTransform(
                self: Surface,
                transform: Output.Transform,
            ) !void {
                _ = self;
                _ = transform;
            }
            pub fn setBufferScale(
                self: Surface,
                scale: i32,
            ) !void {
                _ = self;
                _ = scale;
            }
            pub fn damageBuffer(
                self: Surface,
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
            pub fn offset(
                self: Surface,
                x: i32,
                y: i32,
            ) !void {
                _ = self;
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
        display: wl.Display,
        registry: wl.Registry,
        compositor: wl.Compositor,
        surface: wl.Surface,
        outputs: @import("std").ArrayList(wl.Output),

        pub fn init() State {
            const display: wl.Display = undefined;
            const registry = try display.getRegistry();
            const compositor = try registry.bind(wl.Compositor, .v6, 1);
            const surface = try compositor.createSurface();
            _ = surface;
        }
    };
};
