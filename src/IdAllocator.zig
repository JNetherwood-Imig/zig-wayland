context: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    alloc: *const fn (*anyopaque) ?u32,
    free: *const fn (*anyopaque, id: u32) void,
};

pub const Error = error{OutOfIds};

pub inline fn alloc(self: IdAllocator) Error!u32 {
    return self.vtable.alloc(self.context) orelse error.OutOfIds;
}

pub inline fn free(self: IdAllocator, id: u32) void {
    self.vtable.free(self.context, id);
}

const std = @import("std");

const IdAllocator = @This();
