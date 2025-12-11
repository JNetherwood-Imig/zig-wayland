context: *anyopaque,
vtable: VTable,

pub const VTable = struct {
    alloc: *const fn (*anyopaque) AllocError!u32,
    free: *const fn (*anyopaque, u32) FreeError!void,
};

pub const AllocError = error{
    OutOfIds,
    ImplementationSpecific,
};

pub const FreeError = error{
    OutOfMemory,
    ImplementationSpecific,
};

pub inline fn alloc(self: IdAllocator) AllocError!u32 {
    return self.vtable.alloc(self.context);
}

pub inline fn create(self: IdAllocator, comptime T: type) AllocError!T {
    return @enumFromInt(try self.alloc());
}

pub inline fn free(self: IdAllocator, id: u32) FreeError!void {
    try self.vtable.free(self.context, id);
}

const std = @import("std");
const IdAllocator = @This();
