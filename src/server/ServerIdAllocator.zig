const ServerIdAllocator = @This();

next_id: u32,
free_list: std.ArrayList(u32),
gpa: Allocator,

pub const Options = packed struct {
    free_list_initial_capacity: usize = 64,
};

pub fn init(gpa: Allocator, options: Options) Allocator.Error!ServerIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
        .gpa = gpa,
    };
}

pub fn deinit(self: *ServerIdAllocator) void {
    self.free_list.deinit(self.gpa);
}

pub fn allocator(self: *ServerIdAllocator) IdAllocator {
    return .{
        .context = self,
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) IdAllocator.AllocError!u32 {
    var self: *ServerIdAllocator = @ptrCast(@alignCast(context));
    if (self.free_list.pop()) |id| return id;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    var self: *ServerIdAllocator = @ptrCast(@alignCast(context));
    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.append(self.gpa, id);
}

const std = @import("std");
const min_id: u32 = 0xff000000;
const max_id: u32 = 0xffffffff;
const Allocator = std.mem.Allocator;
const IdAllocator = @import("IdAllocator.zig");
