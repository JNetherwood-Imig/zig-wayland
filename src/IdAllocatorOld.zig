next_client: u32,
client_free_list: IdList,
next_server: u32,
server_free_list: IdList,

pub fn init(gpa: Allocator) Allocator.Error!IdAllocator {
    return .{
        .next_client = client_min_id,
        .client_free_list = try .initCapacity(gpa, free_list_initial_capacity),
        .next_server = server_min_id,
        .server_free_list = try .initCapacity(gpa, free_list_initial_capacity),
    };
}

pub fn deinit(self: *IdAllocator, gpa: Allocator) void {
    self.client_free_list.deinit(gpa);
    self.server_free_list.deinit(gpa);
}

pub fn allocClient(self: *IdAllocator) AllocError!u32 {
    defer self.next_client += 1;
    return self.next_client;
}

pub fn allocServer(self: *IdAllocator) AllocError!u32 {
    defer self.next_server += 1;
    return self.next_server;
}

pub const AllocError = error{
    OutOfMemory,
    OutOfClientIds,
    OutOfServerIds,
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const IdList = std.ArrayList(u32);

const IdAllocator = @This();

const invalid_id: u32 = 0;
const client_min_id: u32 = 0x00000001;
const client_max_id: u32 = 0xfeffffff;
const server_min_id: u32 = 0xff000000;
const server_max_id: u32 = 0xffffffff;

const free_list_initial_capacity: usize = 64;
