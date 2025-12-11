//! An id allocator with a free-list backed by a fixed buffer, meaning it will never allocate memory,
//! but may run out of space when freeing ids.
//! This is probably not a good choice for large projects,
//! or instances where the maximum number of allocated ids is not able to be estimated,
//! but is very light and performant for small and/or known-demand clients.

const std = @import("std");
const core = @import("core");
const min_id: u32 = 0x00000001;
const max_id: u32 = 0xfeffffff;
const Allocator = std.mem.Allocator;
const IdAllocator = core.IdAllocator;

const FixedBufferIdAllocator = @This();

next_id: u32,
free_list: std.ArrayList(u32),

/// Initialize an allocator state backed by a buffer,
/// whose capacity will be the maximum number of free ids
/// that can be tracked at any given time.
pub fn init(buffer: []u32) FixedBufferIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = .initBuffer(buffer),
    };
}

/// Get an IdAllocator interface for the FixedBufferAllocator
pub fn id_allocator(self: *FixedBufferIdAllocator) IdAllocator {
    return .{
        .context = self,
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) IdAllocator.AllocError!u32 {
    var self: *FixedBufferIdAllocator = @ptrCast(@alignCast(context));
    if (self.free_list.pop()) |id| return id;
    if (self.next_id > max_id) return error.OutOfIds;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    if (id > max_id) @panic("Id is less than client max id. Are you trying to free a server id?");

    var self: *FixedBufferIdAllocator = @ptrCast(@alignCast(context));
    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.appendBounded(id);
}
