const DynamicIdAllocator = @This();

next_id: u32,
free_list: std.ArrayList(u32),
gpa: Allocator,

pub const Options = packed struct {
    free_list_initial_capacity: usize = 64,
};

pub fn init(gpa: Allocator, options: Options) Allocator.Error!DynamicIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
        .gpa = gpa,
    };
}

pub fn deinit(self: *DynamicIdAllocator) void {
    self.free_list.deinit(self.gpa);
}

pub fn allocator(self: *DynamicIdAllocator) IdAllocator {
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
    if (id < min_id) @panic("Id is less than server min id. Are you trying to free a client id?");

    var self: *DynamicIdAllocator = @ptrCast(@alignCast(context));
    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.append(self.gpa, id);
}

const std = @import("std");
const core = @import("core");
const min_id: u32 = 0xff000000;
// Even though the protocol allows allocating 0xffffffff,
// it causes problems with integer overflow, so we're just going to stop one short
const max_id: u32 = 0xfffffffe;
const Allocator = std.mem.Allocator;
const IdAllocator = core.IdAllocator;
