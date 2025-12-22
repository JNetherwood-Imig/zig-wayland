//! An id allocator with a free-list backed by a fixed buffer, meaning it will never allocate memory,
//! but may run out of space when freeing ids.
//! This is probably not a good choice for large projects,
//! or instances where the maximum number of allocated ids is not able to be estimated,
//! but is very light and performant for small and/or known-demand clients.

const std = @import("std");
const IdAllocator = @import("../IdAllocator.zig");

const Bounded = @This();

next_id: u32,
min_id: u32,
max_id: u32,
free_list: std.ArrayList(u32),

/// Initialize an allocator state backed by a buffer,
/// whose capacity will be the maximum number of free ids
/// that can be tracked at any given time.
pub fn init(buffer: []u32, protocol_side: enum { client, server }) Bounded {
    return switch (protocol_side) {
        .client => .{
            .next_id = IdAllocator.client_min_id,
            .min_id = IdAllocator.client_min_id,
            .max_id = IdAllocator.client_max_id,
            .free_list = .initBuffer(buffer),
        },
        .server => .{
            .next_id = IdAllocator.server_min_id,
            .min_id = IdAllocator.server_min_id,
            .max_id = IdAllocator.server_max_id,
            .free_list = .initBuffer(buffer),
        },
    };
}

/// Get an IdAllocator interface for the FixedBufferAllocator
pub fn id_allocator(self: *Bounded) IdAllocator {
    return .{
        .context = self,
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) IdAllocator.AllocError!u32 {
    var self: *Bounded = @ptrCast(@alignCast(context));
    if (self.free_list.pop()) |id| return id;
    if (self.next_id > self.max_id) return error.OutOfIds;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    var self: *Bounded = @ptrCast(@alignCast(context));

    if (id < self.min_id or id > self.max_id)
        return error.InvalidId;

    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.appendBounded(id);
}
