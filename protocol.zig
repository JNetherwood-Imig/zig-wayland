const core = @import("core");
const Fixed = core.Fixed;
const Connection = core.Connection;
const IdAllocator = core.IdAllocator;
pub const wayland = struct {
	pub const Display = enum(u32) {
		_,
		pub fn id(self: Display) u32 {
			return @intFromEnum(self);
		}
		pub const sync_request_opcode = 0;
		pub const sync_request_length = 4;
		pub fn sync(
			self: Display
		) !void {
			_ = self;
		}
		pub const get_registry_request_opcode = 1;
		pub const get_registry_request_length = 4;
		pub fn getRegistry(
			self: Display
		) !void {
			_ = self;
		}
	};
	pub const Registry = enum(u32) {
		_,
		pub fn id(self: Registry) u32 {
			return @intFromEnum(self);
		}
		pub const bind_request_opcode = 0;
		pub const bind_request_length = 4096;
		pub fn bind(
			self: Registry
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
		pub const create_surface_request_opcode = 0;
		pub const create_surface_request_length = 4;
		pub fn createSurface(
			self: Compositor
		) !void {
			_ = self;
		}
		pub const create_region_request_opcode = 1;
		pub const create_region_request_length = 4;
		pub fn createRegion(
			self: Compositor
		) !void {
			_ = self;
		}
	};
	pub const ShmPool = enum(u32) {
		_,
		pub fn id(self: ShmPool) u32 {
			return @intFromEnum(self);
		}
		pub const create_buffer_request_opcode = 0;
		pub const create_buffer_request_length = 24;
		pub fn createBuffer(
			self: ShmPool
		) !void {
			_ = self;
		}
		pub const destroy_request_opcode = 1;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: ShmPool
		) !void {
			_ = self;
		}
		pub const resize_request_opcode = 2;
		pub const resize_request_length = 4;
		pub fn resize(
			self: ShmPool
		) !void {
			_ = self;
		}
	};
	pub const Shm = enum(u32) {
		_,
		pub fn id(self: Shm) u32 {
			return @intFromEnum(self);
		}
		pub const create_pool_request_opcode = 0;
		pub const create_pool_request_length = 8;
		pub fn createPool(
			self: Shm
		) !void {
			_ = self;
		}
		pub const release_request_opcode = 1;
		pub const release_request_length = 0;
		pub fn release(
			self: Shm
		) !void {
			_ = self;
		}
	};
	pub const Buffer = enum(u32) {
		_,
		pub fn id(self: Buffer) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Buffer
		) !void {
			_ = self;
		}
	};
	pub const DataOffer = enum(u32) {
		_,
		pub fn id(self: DataOffer) u32 {
			return @intFromEnum(self);
		}
		pub const accept_request_opcode = 0;
		pub const accept_request_length = 4096;
		pub fn accept(
			self: DataOffer
		) !void {
			_ = self;
		}
		pub const receive_request_opcode = 1;
		pub const receive_request_length = 4096;
		pub fn receive(
			self: DataOffer
		) !void {
			_ = self;
		}
		pub const destroy_request_opcode = 2;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: DataOffer
		) !void {
			_ = self;
		}
		pub const finish_request_opcode = 3;
		pub const finish_request_length = 0;
		pub fn finish(
			self: DataOffer
		) !void {
			_ = self;
		}
		pub const set_actions_request_opcode = 4;
		pub const set_actions_request_length = 8;
		pub fn setActions(
			self: DataOffer
		) !void {
			_ = self;
		}
	};
	pub const DataSource = enum(u32) {
		_,
		pub fn id(self: DataSource) u32 {
			return @intFromEnum(self);
		}
		pub const offer_request_opcode = 0;
		pub const offer_request_length = 4096;
		pub fn offer(
			self: DataSource
		) !void {
			_ = self;
		}
		pub const destroy_request_opcode = 1;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: DataSource
		) !void {
			_ = self;
		}
		pub const set_actions_request_opcode = 2;
		pub const set_actions_request_length = 4;
		pub fn setActions(
			self: DataSource
		) !void {
			_ = self;
		}
	};
	pub const DataDevice = enum(u32) {
		_,
		pub fn id(self: DataDevice) u32 {
			return @intFromEnum(self);
		}
		pub const start_drag_request_opcode = 0;
		pub const start_drag_request_length = 16;
		pub fn startDrag(
			self: DataDevice
		) !void {
			_ = self;
		}
		pub const set_selection_request_opcode = 1;
		pub const set_selection_request_length = 8;
		pub fn setSelection(
			self: DataDevice
		) !void {
			_ = self;
		}
		pub const release_request_opcode = 2;
		pub const release_request_length = 0;
		pub fn release(
			self: DataDevice
		) !void {
			_ = self;
		}
	};
	pub const DataDeviceManager = enum(u32) {
		_,
		pub fn id(self: DataDeviceManager) u32 {
			return @intFromEnum(self);
		}
		pub const create_data_source_request_opcode = 0;
		pub const create_data_source_request_length = 4;
		pub fn createDataSource(
			self: DataDeviceManager
		) !void {
			_ = self;
		}
		pub const get_data_device_request_opcode = 1;
		pub const get_data_device_request_length = 8;
		pub fn getDataDevice(
			self: DataDeviceManager
		) !void {
			_ = self;
		}
	};
	pub const Shell = enum(u32) {
		_,
		pub fn id(self: Shell) u32 {
			return @intFromEnum(self);
		}
		pub const get_shell_surface_request_opcode = 0;
		pub const get_shell_surface_request_length = 8;
		pub fn getShellSurface(
			self: Shell
		) !void {
			_ = self;
		}
	};
	pub const ShellSurface = enum(u32) {
		_,
		pub fn id(self: ShellSurface) u32 {
			return @intFromEnum(self);
		}
		pub const pong_request_opcode = 0;
		pub const pong_request_length = 4;
		pub fn pong(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const move_request_opcode = 1;
		pub const move_request_length = 8;
		pub fn move(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const resize_request_opcode = 2;
		pub const resize_request_length = 12;
		pub fn resize(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_toplevel_request_opcode = 3;
		pub const set_toplevel_request_length = 0;
		pub fn setToplevel(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_transient_request_opcode = 4;
		pub const set_transient_request_length = 16;
		pub fn setTransient(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_fullscreen_request_opcode = 5;
		pub const set_fullscreen_request_length = 12;
		pub fn setFullscreen(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_popup_request_opcode = 6;
		pub const set_popup_request_length = 24;
		pub fn setPopup(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_maximized_request_opcode = 7;
		pub const set_maximized_request_length = 4;
		pub fn setMaximized(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_title_request_opcode = 8;
		pub const set_title_request_length = 4096;
		pub fn setTitle(
			self: ShellSurface
		) !void {
			_ = self;
		}
		pub const set_class_request_opcode = 9;
		pub const set_class_request_length = 4096;
		pub fn setClass(
			self: ShellSurface
		) !void {
			_ = self;
		}
	};
	pub const Surface = enum(u32) {
		_,
		pub fn id(self: Surface) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Surface
		) !void {
			_ = self;
		}
		pub const attach_request_opcode = 1;
		pub const attach_request_length = 12;
		pub fn attach(
			self: Surface
		) !void {
			_ = self;
		}
		pub const damage_request_opcode = 2;
		pub const damage_request_length = 16;
		pub fn damage(
			self: Surface
		) !void {
			_ = self;
		}
		pub const frame_request_opcode = 3;
		pub const frame_request_length = 4;
		pub fn frame(
			self: Surface
		) !void {
			_ = self;
		}
		pub const set_opaque_region_request_opcode = 4;
		pub const set_opaque_region_request_length = 4;
		pub fn setOpaqueRegion(
			self: Surface
		) !void {
			_ = self;
		}
		pub const set_input_region_request_opcode = 5;
		pub const set_input_region_request_length = 4;
		pub fn setInputRegion(
			self: Surface
		) !void {
			_ = self;
		}
		pub const commit_request_opcode = 6;
		pub const commit_request_length = 0;
		pub fn commit(
			self: Surface
		) !void {
			_ = self;
		}
		pub const set_buffer_transform_request_opcode = 7;
		pub const set_buffer_transform_request_length = 4;
		pub fn setBufferTransform(
			self: Surface
		) !void {
			_ = self;
		}
		pub const set_buffer_scale_request_opcode = 8;
		pub const set_buffer_scale_request_length = 4;
		pub fn setBufferScale(
			self: Surface
		) !void {
			_ = self;
		}
		pub const damage_buffer_request_opcode = 9;
		pub const damage_buffer_request_length = 16;
		pub fn damageBuffer(
			self: Surface
		) !void {
			_ = self;
		}
		pub const offset_request_opcode = 10;
		pub const offset_request_length = 8;
		pub fn offset(
			self: Surface
		) !void {
			_ = self;
		}
	};
	pub const Seat = enum(u32) {
		_,
		pub fn id(self: Seat) u32 {
			return @intFromEnum(self);
		}
		pub const get_pointer_request_opcode = 0;
		pub const get_pointer_request_length = 4;
		pub fn getPointer(
			self: Seat
		) !void {
			_ = self;
		}
		pub const get_keyboard_request_opcode = 1;
		pub const get_keyboard_request_length = 4;
		pub fn getKeyboard(
			self: Seat
		) !void {
			_ = self;
		}
		pub const get_touch_request_opcode = 2;
		pub const get_touch_request_length = 4;
		pub fn getTouch(
			self: Seat
		) !void {
			_ = self;
		}
		pub const release_request_opcode = 3;
		pub const release_request_length = 0;
		pub fn release(
			self: Seat
		) !void {
			_ = self;
		}
	};
	pub const Pointer = enum(u32) {
		_,
		pub fn id(self: Pointer) u32 {
			return @intFromEnum(self);
		}
		pub const set_cursor_request_opcode = 0;
		pub const set_cursor_request_length = 16;
		pub fn setCursor(
			self: Pointer
		) !void {
			_ = self;
		}
		pub const release_request_opcode = 1;
		pub const release_request_length = 0;
		pub fn release(
			self: Pointer
		) !void {
			_ = self;
		}
	};
	pub const Keyboard = enum(u32) {
		_,
		pub fn id(self: Keyboard) u32 {
			return @intFromEnum(self);
		}
		pub const release_request_opcode = 0;
		pub const release_request_length = 0;
		pub fn release(
			self: Keyboard
		) !void {
			_ = self;
		}
	};
	pub const Touch = enum(u32) {
		_,
		pub fn id(self: Touch) u32 {
			return @intFromEnum(self);
		}
		pub const release_request_opcode = 0;
		pub const release_request_length = 0;
		pub fn release(
			self: Touch
		) !void {
			_ = self;
		}
	};
	pub const Output = enum(u32) {
		_,
		pub fn id(self: Output) u32 {
			return @intFromEnum(self);
		}
		pub const release_request_opcode = 0;
		pub const release_request_length = 0;
		pub fn release(
			self: Output
		) !void {
			_ = self;
		}
	};
	pub const Region = enum(u32) {
		_,
		pub fn id(self: Region) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Region
		) !void {
			_ = self;
		}
		pub const add_request_opcode = 1;
		pub const add_request_length = 16;
		pub fn add(
			self: Region
		) !void {
			_ = self;
		}
		pub const subtract_request_opcode = 2;
		pub const subtract_request_length = 16;
		pub fn subtract(
			self: Region
		) !void {
			_ = self;
		}
	};
	pub const Subcompositor = enum(u32) {
		_,
		pub fn id(self: Subcompositor) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Subcompositor
		) !void {
			_ = self;
		}
		pub const get_subsurface_request_opcode = 1;
		pub const get_subsurface_request_length = 12;
		pub fn getSubsurface(
			self: Subcompositor
		) !void {
			_ = self;
		}
	};
	pub const Subsurface = enum(u32) {
		_,
		pub fn id(self: Subsurface) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Subsurface
		) !void {
			_ = self;
		}
		pub const set_position_request_opcode = 1;
		pub const set_position_request_length = 8;
		pub fn setPosition(
			self: Subsurface
		) !void {
			_ = self;
		}
		pub const place_above_request_opcode = 2;
		pub const place_above_request_length = 4;
		pub fn placeAbove(
			self: Subsurface
		) !void {
			_ = self;
		}
		pub const place_below_request_opcode = 3;
		pub const place_below_request_length = 4;
		pub fn placeBelow(
			self: Subsurface
		) !void {
			_ = self;
		}
		pub const set_sync_request_opcode = 4;
		pub const set_sync_request_length = 0;
		pub fn setSync(
			self: Subsurface
		) !void {
			_ = self;
		}
		pub const set_desync_request_opcode = 5;
		pub const set_desync_request_length = 0;
		pub fn setDesync(
			self: Subsurface
		) !void {
			_ = self;
		}
	};
	pub const Fixes = enum(u32) {
		_,
		pub fn id(self: Fixes) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Fixes
		) !void {
			_ = self;
		}
		pub const destroy_registry_request_opcode = 1;
		pub const destroy_registry_request_length = 4;
		pub fn destroyRegistry(
			self: Fixes
		) !void {
			_ = self;
		}
	};
};
pub const xdg_shell = struct {
	pub const WmBase = enum(u32) {
		_,
		pub fn id(self: WmBase) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: WmBase
		) !void {
			_ = self;
		}
		pub const create_positioner_request_opcode = 1;
		pub const create_positioner_request_length = 4;
		pub fn createPositioner(
			self: WmBase
		) !void {
			_ = self;
		}
		pub const get_xdg_surface_request_opcode = 2;
		pub const get_xdg_surface_request_length = 8;
		pub fn getXdgSurface(
			self: WmBase
		) !void {
			_ = self;
		}
		pub const pong_request_opcode = 3;
		pub const pong_request_length = 4;
		pub fn pong(
			self: WmBase
		) !void {
			_ = self;
		}
	};
	pub const Positioner = enum(u32) {
		_,
		pub fn id(self: Positioner) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_size_request_opcode = 1;
		pub const set_size_request_length = 8;
		pub fn setSize(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_anchor_rect_request_opcode = 2;
		pub const set_anchor_rect_request_length = 16;
		pub fn setAnchorRect(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_anchor_request_opcode = 3;
		pub const set_anchor_request_length = 4;
		pub fn setAnchor(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_gravity_request_opcode = 4;
		pub const set_gravity_request_length = 4;
		pub fn setGravity(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_constraint_adjustment_request_opcode = 5;
		pub const set_constraint_adjustment_request_length = 4;
		pub fn setConstraintAdjustment(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_offset_request_opcode = 6;
		pub const set_offset_request_length = 8;
		pub fn setOffset(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_reactive_request_opcode = 7;
		pub const set_reactive_request_length = 0;
		pub fn setReactive(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_parent_size_request_opcode = 8;
		pub const set_parent_size_request_length = 8;
		pub fn setParentSize(
			self: Positioner
		) !void {
			_ = self;
		}
		pub const set_parent_configure_request_opcode = 9;
		pub const set_parent_configure_request_length = 4;
		pub fn setParentConfigure(
			self: Positioner
		) !void {
			_ = self;
		}
	};
	pub const Surface = enum(u32) {
		_,
		pub fn id(self: Surface) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Surface
		) !void {
			_ = self;
		}
		pub const get_toplevel_request_opcode = 1;
		pub const get_toplevel_request_length = 4;
		pub fn getToplevel(
			self: Surface
		) !void {
			_ = self;
		}
		pub const get_popup_request_opcode = 2;
		pub const get_popup_request_length = 12;
		pub fn getPopup(
			self: Surface
		) !void {
			_ = self;
		}
		pub const set_window_geometry_request_opcode = 3;
		pub const set_window_geometry_request_length = 16;
		pub fn setWindowGeometry(
			self: Surface
		) !void {
			_ = self;
		}
		pub const ack_configure_request_opcode = 4;
		pub const ack_configure_request_length = 4;
		pub fn ackConfigure(
			self: Surface
		) !void {
			_ = self;
		}
	};
	pub const Toplevel = enum(u32) {
		_,
		pub fn id(self: Toplevel) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_parent_request_opcode = 1;
		pub const set_parent_request_length = 4;
		pub fn setParent(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_title_request_opcode = 2;
		pub const set_title_request_length = 4096;
		pub fn setTitle(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_app_id_request_opcode = 3;
		pub const set_app_id_request_length = 4096;
		pub fn setAppId(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const show_window_menu_request_opcode = 4;
		pub const show_window_menu_request_length = 16;
		pub fn showWindowMenu(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const move_request_opcode = 5;
		pub const move_request_length = 8;
		pub fn move(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const resize_request_opcode = 6;
		pub const resize_request_length = 12;
		pub fn resize(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_max_size_request_opcode = 7;
		pub const set_max_size_request_length = 8;
		pub fn setMaxSize(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_min_size_request_opcode = 8;
		pub const set_min_size_request_length = 8;
		pub fn setMinSize(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_maximized_request_opcode = 9;
		pub const set_maximized_request_length = 0;
		pub fn setMaximized(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const unset_maximized_request_opcode = 10;
		pub const unset_maximized_request_length = 0;
		pub fn unsetMaximized(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_fullscreen_request_opcode = 11;
		pub const set_fullscreen_request_length = 4;
		pub fn setFullscreen(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const unset_fullscreen_request_opcode = 12;
		pub const unset_fullscreen_request_length = 0;
		pub fn unsetFullscreen(
			self: Toplevel
		) !void {
			_ = self;
		}
		pub const set_minimized_request_opcode = 13;
		pub const set_minimized_request_length = 0;
		pub fn setMinimized(
			self: Toplevel
		) !void {
			_ = self;
		}
	};
	pub const Popup = enum(u32) {
		_,
		pub fn id(self: Popup) u32 {
			return @intFromEnum(self);
		}
		pub const destroy_request_opcode = 0;
		pub const destroy_request_length = 0;
		pub fn destroy(
			self: Popup
		) !void {
			_ = self;
		}
		pub const grab_request_opcode = 1;
		pub const grab_request_length = 8;
		pub fn grab(
			self: Popup
		) !void {
			_ = self;
		}
		pub const reposition_request_opcode = 2;
		pub const reposition_request_length = 8;
		pub fn reposition(
			self: Popup
		) !void {
			_ = self;
		}
	};
};
