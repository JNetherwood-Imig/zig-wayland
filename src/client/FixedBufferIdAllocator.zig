const FixedBufferIdAllocator = @This();

next_id: u32,
free_list: std.ArrayList(u32),

pub fn init(buffer: []u32) FixedBufferIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = .initBuffer(buffer),
    };
}

pub fn allocator(self: *FixedBufferIdAllocator) IdAllocator {
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
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    var self: *FixedBufferIdAllocator = @ptrCast(@alignCast(context));
    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.appendBounded(id);
}

const std = @import("std");
const core = @import("core");
const min_id: u32 = 0x00000001;
const max_id: u32 = 0xfeffffff;
const Allocator = std.mem.Allocator;
const IdAllocator = core.IdAllocator;
