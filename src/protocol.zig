const core = @import("core");
const Proxy = core.Proxy;

pub const wayland = struct {
    pub const WlDisplay = struct {
        proxy: Proxy = .dummy,

        pub fn sync(
            self: *const WlDisplay,
        ) wayland.WlCallback {
            const callback = wayland.WlCallback{};
            const msg = core.wire.Message.init(self.proxy.id, 0, .{
                callback,
            });
            _ = msg;
            return callback;
        }

        pub fn getRegistry(
            self: *const WlDisplay,
        ) wayland.WlRegistry {
            const registry = wayland.WlRegistry{};
            const msg = core.wire.Message.init(self.proxy.id, 1, .{
                registry,
            });
            _ = msg;
            return registry;
        }
    };
    pub const WlCallback = struct {
        proxy: Proxy = .dummy,
    };
    pub const WlRegistry = struct {
        proxy: Proxy = .dummy,

        pub fn bind(
            self: *const WlRegistry,
            comptime Interface: type,
            name: u32,
            version: u32,
        ) Interface {
            const new_object = Interface{};
            const msg = core.wire.Message.init(self.proxy.id, 0, .{
                name,
                core.wire.GenericNewId{
                    .interface = Interface.interface,
                    .version = version,
                    .new_id = new_object.proxy.id,
                },
            });
            _ = msg;
            return new_object;
        }
    };
};
