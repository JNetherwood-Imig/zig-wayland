//! An id allocator which uses a general-purpose allocator to track ids without bounds.
//! It is almost always the correct choice for large clients.

const std = @import("std");
const client_min_id: u32 = 0x00000001;
const client_max_id: u32 = 0xfeffffff;
const server_min_id: u32 = 0xff000000;
const server_max_id: u32 = 0xfffffffe;
const IdAllocator = @import("../IdAllocator.zig");

const Unbounded = @This();

next_id: u32,
min_id: u32,
max_id: u32,
free_list: std.ArrayList(u32),
gpa: std.mem.Allocator,

pub const Options = packed struct {
    free_list_initial_capacity: usize = 64,
};

/// Initialize the id allocator state with space for options.free_list_initial_capacity
/// elements in free-list (arbitrarily defaults to 64)
pub fn init(
    gpa: std.mem.Allocator,
    protocol_side: enum { client, server },
    options: Options,
) std.mem.Allocator.Error!Unbounded {
    return switch (protocol_side) {
        .client => .{
            .next_id = client_min_id,
            .min_id = client_min_id,
            .max_id = client_max_id,
            .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
            .gpa = gpa,
        },
        .server => .{
            .next_id = server_min_id,
            .min_id = server_min_id,
            .max_id = server_max_id,
            .free_list = try .initCapacity(gpa, options.free_list_initial_capacity),
            .gpa = gpa,
        },
    };
}

/// Free the memory for the free-list
pub fn deinit(self: *Unbounded) void {
    self.free_list.deinit(self.gpa);
}

/// Get an IdAllocator interface for the DynamicIdAllocator
pub fn id_allocator(self: *Unbounded) IdAllocator {
    return .{
        .context = self,
        .vtable = .{
            .alloc = alloc,
            .free = free,
        },
    };
}

fn alloc(context: *anyopaque) IdAllocator.AllocError!u32 {
    var self: *Unbounded = @ptrCast(@alignCast(context));
    if (self.free_list.pop()) |id| return id;
    if (self.next_id > self.max_id) return error.OutOfIds;
    defer self.next_id += 1;
    return self.next_id;
}

fn free(context: *anyopaque, id: u32) IdAllocator.FreeError!void {
    var self: *Unbounded = @ptrCast(@alignCast(context));

    std.debug.assert(id >= self.min_id and id <= self.max_id);

    if (id == self.next_id - 1)
        self.next_id = id
    else
        try self.free_list.append(self.gpa, id);
}
