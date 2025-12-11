const Display = @This();

inner: wl.Display,
sync_callback: ?wl.Callback = null,

pub fn getRegistry(
    self: *Display,
    gpa: Allocator,
    connection: *core.Connection,
    ida: core.IdAllocator,
) !Registry {
    _ = gpa;
    const registry = try self.inner.getRegistry(connection, ida);
    _ = registry;
    // while (try self.roundtrip(connection, ida)) |event| switch (event) {
    //  .wl_registry_global => |global| try registry.register(gpa, global.name, global.interface, global.version),
    //  .wl_registry_global_remove => |global_remove| try registry.unregister(gpa, global_remove.name)
    //  else => |ev| log.warn("Intercepted unexpected event {t}.", .{ev}),
    // }
}

// TODO: return !?protocol.Event
pub fn roundtrip(self: *Display, connection: *core.Connection, ida: core.IdAllocator) !void {
    if (self.sync_callback == null)
        self.sync_callback = self.inner.sync(connection, ida);
    if (self.sync_callback) |cb| {
        _ = cb;
        // while (connection.waitEvent()) |event| {
        //  if event is wl.Callback.DoneEvent and event.wl_callback is sync_callback then:
        //      self.sync_callback = null
        //      return null
        // } else |err| return err;
    }
    return null;
}

const std = @import("std");
const core = @import("core");
const wl = @import("protocol").wayland;
const Registry = @import("Registry.zig");
const Allocator = std.mem.Allocator;
