pub const zwl = struct {
    const IdAllocator = struct {};
    const Connection = struct {
        pub fn sendMessage(
            object: u32,
            opcode: u16,
            length: u16,
            buffer: []const u8,
        ) !void {
            _ = object;
            _ = opcode;
            _ = length;
            _ = buffer;
        }

        pub fn sendMessageWithFds(
            object: u32,
            opcode: u16,
            length: u16,
            buffer: []const u8,
            comptime fd_length: usize,
            fd_buffer: []const i32,
        ) !void {
            _ = object;
            _ = opcode;
            _ = length;
            _ = buffer;
            _ = fd_length;
            _ = fd_buffer;
        }
    };
};
pub const protocol = struct {
    pub const wayland = struct {
        pub const Display = enum(u32) {
            _,

            pub const sync_request_opcode: u16 = 0;
            pub const sync_request_length: u16 = 12;

            pub fn id(self: Display) u32 {
                return @intFromEnum(self);
            }

            pub fn sync(
                self: Display,
                connection: zwl.Connection,
                id_allocator: zwl.IdAllocator,
            ) !wayland.Callback {
                var buffer: [sync_request_length]u8 = undefined;
                const callback = try id_allocator.alloc();
                try self.serializeSync(&buffer, callback);
                try connection.sendMessage(
                    self.id(),
                    sync_request_opcode,
                    sync_request_length,
                    &buffer,
                );
            }

            pub fn serializeSync(
                self: Display,
                buffer: []u8,
                callback: u32,
            ) !void {
                if (buffer.len < sync_request_length)
                    return error.BufferTooSmall;
                _ = self;
                _ = callback;
            }
        };
    };
};
