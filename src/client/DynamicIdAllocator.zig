//! An id allocator which uses a general-purpose allocator to track ids without bounds.
//! It is almost always the correct choice for large clients.

const std = @import("std");
const core = @import("core");
const min_id: u32 = 0x00000001;
const max_id: u32 = 0xfeffffff;
const Allocator = std.mem.Allocator;
const IdAllocator = core.IdAllocator;

const DynamicIdAllocator = @This();

next_id: u32,
free_list: std.ArrayList(u32),
gpa: Allocator,

pub const Options = packed struct {
    free_list_initial_capacity: usize = 64,
};

/// Initialize the id allocator state with space for options.free_list_initial_capacity
/// elements in free-list (arbitrarily defaults to 64)
pub fn init(gpa: Allocator, options: Options) Allocator.Error!DynamicIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
        .gpa = gpa,
    };
}

/// Free the memory for the free-list
pub fn deinit(self: *DynamicIdAllocator) void {
    self.free_list.deinit(self.gpa);
}

/// Get an IdAllocator interface for the DynamicIdAllocator
pub fn id_allocator(self: *DynamicIdAllocator) IdAllocator {
    return .{
        .context = self,
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) IdAllocator.AllocError!u32 {
    var self: *DynamicIdAllocator = @ptrCast(@alignCast(context));
    if (self.free_list.pop()) |id| return id;
    if (self.next_id > max_id) return error.OutOfIds;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    if (id > max_id) @panic("Id is less than client max id. Are you trying to free a server id?");

    var self: *DynamicIdAllocator = @ptrCast(@alignCast(context));
    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.append(self.gpa, id);
}
