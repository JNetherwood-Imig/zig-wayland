const std = @import("std");
const zwl = @import("zwl");
const vk = @import("vulkan");

var libvulkan: ?std.DynLib = null;
var vkb: vk.BaseWrapper = undefined;
var vki: vk.InstanceWrapper = undefined;
var vkd: vk.DeviceWrapper = undefined;

fn libvulkanBaseLoader(_: vk.Instance, name_ptr: [*:0]const u8) vk.PfnVoidFunction {
    const name = std.mem.span(name_ptr);
    return libvulkan.?.lookup(vk.PfnVoidFunction, name).?;
}

pub fn main() !void {
    libvulkan = try std.DynLib.open("libvulkan.so.1");
    defer if (libvulkan) |*lv| lv.close();
    vkb = vk.BaseWrapper.load(libvulkanBaseLoader);
}
