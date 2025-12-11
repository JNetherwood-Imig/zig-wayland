next_id: u32,
free_list: std.ArrayList(u32),
gpa: Allocator,

pub const Options = packed struct {
    free_list_initial_capacity: usize = 64,
};

pub fn init(gpa: Allocator, options: Options) !ClientIdAllocator {
    return .{
        .next_id = min_id,
        .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
        .gpa = gpa,
    };
}

pub fn deinit(self: *ClientIdAllocator) void {
    self.free_list.deinit(self.gpa);
}

pub fn allocator(self: *ClientIdAllocator) IdAllocator {
    return .{
        .context = @ptrCast(self),
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) ?u32 {
    var self: *ClientIdAllocator = @ptrCast(context);
    if (self.free_list.pop()) |id| return id;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) void {
    var self: *ClientIdAllocator = @ptrCast(context);
    if (id == self.next_id - 1)
        self.next_id = id
    else
        self.free_list.append(self.gpa, id) catch unreachable;
}

const std = @import("std");
const IdAllocator = @import("IdAllocator.zig");
const Allocator = std.mem.Allocator;

const min_id: u32 = 0xff000000;
const max_id: u32 = 0xffffffff;
const ClientIdAllocator = @This();
