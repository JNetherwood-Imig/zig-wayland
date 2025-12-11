pub const wayland = struct {
	pub const Display = enum(u32) {
		_,
		pub fn id(self: Display) u32 {
			return @intFromEnum(self);
		}
		pub fn sync(
			self: Display,
		) !void {
			_ = self;
		}
		pub fn getRegistry(
			self: Display,
		) !void {
			_ = self;
		}
	};
	pub const Registry = enum(u32) {
		_,
		pub fn id(self: Registry) u32 {
			return @intFromEnum(self);
		}
		pub fn bind(
			self: Registry,
		) !void {
			_ = self;
		}
	};
	pub const Callback = enum(u32) {
		_,
		pub fn id(self: Callback) u32 {
			return @intFromEnum(self);
		}
	};
	pub const Compositor = enum(u32) {
		_,
		pub fn id(self: Compositor) u32 {
			return @intFromEnum(self);
		}
		pub fn createSurface(
			self: Compositor,
		) !void {
			_ = self;
		}
		pub fn createRegion(
			self: Compositor,
		) !void {
			_ = self;
		}
	};
	pub const ShmPool = enum(u32) {
		_,
		pub fn id(self: ShmPool) u32 {
			return @intFromEnum(self);
		}
		pub fn createBuffer(
			self: ShmPool,
		) !void {
			_ = self;
		}
		pub fn destroy(
			self: ShmPool,
		) !void {
			_ = self;
		}
		pub fn resize(
			self: ShmPool,
		) !void {
			_ = self;
		}
	};
	pub const Shm = enum(u32) {
		_,
		pub fn id(self: Shm) u32 {
			return @intFromEnum(self);
		}
		pub fn createPool(
			self: Shm,
		) !void {
			_ = self;
		}
		pub fn release(
			self: Shm,
		) !void {
			_ = self;
		}
	};
	pub const Buffer = enum(u32) {
		_,
		pub fn id(self: Buffer) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Buffer,
		) !void {
			_ = self;
		}
	};
	pub const DataOffer = enum(u32) {
		_,
		pub fn id(self: DataOffer) u32 {
			return @intFromEnum(self);
		}
		pub fn accept(
			self: DataOffer,
		) !void {
			_ = self;
		}
		pub fn receive(
			self: DataOffer,
		) !void {
			_ = self;
		}
		pub fn destroy(
			self: DataOffer,
		) !void {
			_ = self;
		}
		pub fn finish(
			self: DataOffer,
		) !void {
			_ = self;
		}
		pub fn setActions(
			self: DataOffer,
		) !void {
			_ = self;
		}
	};
	pub const DataSource = enum(u32) {
		_,
		pub fn id(self: DataSource) u32 {
			return @intFromEnum(self);
		}
		pub fn offer(
			self: DataSource,
		) !void {
			_ = self;
		}
		pub fn destroy(
			self: DataSource,
		) !void {
			_ = self;
		}
		pub fn setActions(
			self: DataSource,
		) !void {
			_ = self;
		}
	};
	pub const DataDevice = enum(u32) {
		_,
		pub fn id(self: DataDevice) u32 {
			return @intFromEnum(self);
		}
		pub fn startDrag(
			self: DataDevice,
		) !void {
			_ = self;
		}
		pub fn setSelection(
			self: DataDevice,
		) !void {
			_ = self;
		}
		pub fn release(
			self: DataDevice,
		) !void {
			_ = self;
		}
	};
	pub const DataDeviceManager = enum(u32) {
		_,
		pub fn id(self: DataDeviceManager) u32 {
			return @intFromEnum(self);
		}
		pub fn createDataSource(
			self: DataDeviceManager,
		) !void {
			_ = self;
		}
		pub fn getDataDevice(
			self: DataDeviceManager,
		) !void {
			_ = self;
		}
	};
	pub const Shell = enum(u32) {
		_,
		pub fn id(self: Shell) u32 {
			return @intFromEnum(self);
		}
		pub fn getShellSurface(
			self: Shell,
		) !void {
			_ = self;
		}
	};
	pub const ShellSurface = enum(u32) {
		_,
		pub fn id(self: ShellSurface) u32 {
			return @intFromEnum(self);
		}
		pub fn pong(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn move(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn resize(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setToplevel(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setTransient(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setFullscreen(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setPopup(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setMaximized(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setTitle(
			self: ShellSurface,
		) !void {
			_ = self;
		}
		pub fn setClass(
			self: ShellSurface,
		) !void {
			_ = self;
		}
	};
	pub const Surface = enum(u32) {
		_,
		pub fn id(self: Surface) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn attach(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn damage(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn frame(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn setOpaqueRegion(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn setInputRegion(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn commit(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn setBufferTransform(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn setBufferScale(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn damageBuffer(
			self: Surface,
		) !void {
			_ = self;
		}
		pub fn offset(
			self: Surface,
		) !void {
			_ = self;
		}
	};
	pub const Seat = enum(u32) {
		_,
		pub fn id(self: Seat) u32 {
			return @intFromEnum(self);
		}
		pub fn getPointer(
			self: Seat,
		) !void {
			_ = self;
		}
		pub fn getKeyboard(
			self: Seat,
		) !void {
			_ = self;
		}
		pub fn getTouch(
			self: Seat,
		) !void {
			_ = self;
		}
		pub fn release(
			self: Seat,
		) !void {
			_ = self;
		}
	};
	pub const Pointer = enum(u32) {
		_,
		pub fn id(self: Pointer) u32 {
			return @intFromEnum(self);
		}
		pub fn setCursor(
			self: Pointer,
		) !void {
			_ = self;
		}
		pub fn release(
			self: Pointer,
		) !void {
			_ = self;
		}
	};
	pub const Keyboard = enum(u32) {
		_,
		pub fn id(self: Keyboard) u32 {
			return @intFromEnum(self);
		}
		pub fn release(
			self: Keyboard,
		) !void {
			_ = self;
		}
	};
	pub const Touch = enum(u32) {
		_,
		pub fn id(self: Touch) u32 {
			return @intFromEnum(self);
		}
		pub fn release(
			self: Touch,
		) !void {
			_ = self;
		}
	};
	pub const Output = enum(u32) {
		_,
		pub fn id(self: Output) u32 {
			return @intFromEnum(self);
		}
		pub fn release(
			self: Output,
		) !void {
			_ = self;
		}
	};
	pub const Region = enum(u32) {
		_,
		pub fn id(self: Region) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Region,
		) !void {
			_ = self;
		}
		pub fn add(
			self: Region,
		) !void {
			_ = self;
		}
		pub fn subtract(
			self: Region,
		) !void {
			_ = self;
		}
	};
	pub const Subcompositor = enum(u32) {
		_,
		pub fn id(self: Subcompositor) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Subcompositor,
		) !void {
			_ = self;
		}
		pub fn getSubsurface(
			self: Subcompositor,
		) !void {
			_ = self;
		}
	};
	pub const Subsurface = enum(u32) {
		_,
		pub fn id(self: Subsurface) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Subsurface,
		) !void {
			_ = self;
		}
		pub fn setPosition(
			self: Subsurface,
		) !void {
			_ = self;
		}
		pub fn placeAbove(
			self: Subsurface,
		) !void {
			_ = self;
		}
		pub fn placeBelow(
			self: Subsurface,
		) !void {
			_ = self;
		}
		pub fn setSync(
			self: Subsurface,
		) !void {
			_ = self;
		}
		pub fn setDesync(
			self: Subsurface,
		) !void {
			_ = self;
		}
	};
	pub const Fixes = enum(u32) {
		_,
		pub fn id(self: Fixes) u32 {
			return @intFromEnum(self);
		}
		pub fn destroy(
			self: Fixes,
		) !void {
			_ = self;
		}
		pub fn destroyRegistry(
			self: Fixes,
		) !void {
			_ = self;
		}
	};
};
