const UnionFieldAttrs = @import("std").builtin.Type.UnionField.Attributes;
/// Takes a tuple of generated protocols and returns a 2-level tagged union.
/// The toplevel field corresponds to the interface, and the inner field
/// contains each incoming message type for that interface.
/// Calling `MessageUnion(.{ wayland, xdg_shell })` would produce the following output.
///
/// ```
/// union(enum) {
///     wl_display: union(enum) {
///         delete_id: wayland.Display.DeleteIdMessage,
///         @"error": wayland.Display.ErrorMessage,
///     },
///     ...
///     xdg_wm_base: union(enum) {
///         ping: xdg_shell.WmBase.PingMessage,
///     },
/// };
/// ```
pub fn MessageUnion(comptime protocols: anytype) type {
    comptime var field_names: []const []const u8 = &.{};
    comptime var enum_values: []const u32 = &.{};
    comptime var union_types: []const type = &.{};
    comptime var union_attrs: []const UnionFieldAttrs = &.{};
    comptime var next_value: u32 = 0;

    inline for (@typeInfo(@TypeOf(protocols)).@"struct".fields) |protocol_field| {
        const protocol = @field(protocols, protocol_field.name);
        inline for (@typeInfo(protocol).@"struct".decls) |interface_decl| {
            const interface = @field(protocol, interface_decl.name);
            if (InterfaceMessageUnion(interface)) |Message| {
                field_names = field_names ++ [_][]const u8{interface.interface};
                union_types = union_types ++ [_]type{Message};
                union_attrs = union_attrs ++ [_]UnionFieldAttrs{.{ .@"align" = @alignOf(Message) }};
                enum_values = enum_values ++ [_]u32{next_value};
                next_value += 1;
            }
        }
    }

    const backing_enum = @Enum(u32, .exhaustive, field_names, @ptrCast(enum_values.ptr));
    return @Union(.auto, backing_enum, field_names, @ptrCast(union_types.ptr), @ptrCast(union_attrs.ptr));
}

fn InterfaceMessageUnion(comptime Interface: type) ?type {
    comptime var field_names: []const []const u8 = &.{};
    comptime var enum_values: []const u32 = &.{};
    comptime var union_types: []const type = &.{};
    comptime var union_attrs: []const UnionFieldAttrs = &.{};
    comptime var next_value: u32 = 0;

    inline for (@typeInfo(Interface).@"enum".decls) |maybe_message_decl| {
        const maybe_message = @field(Interface, maybe_message_decl.name);
        switch (@typeInfo(@TypeOf(maybe_message))) {
            .type => {
                if (@hasDecl(maybe_message, "_name") and
                    @hasDecl(maybe_message, "_signature") and
                    @hasDecl(maybe_message, "_opcode"))
                {
                    field_names = field_names ++ [_][]const u8{@field(maybe_message, "_name")};
                    union_types = union_types ++ [_]type{maybe_message};
                    union_attrs = union_attrs ++ [_]UnionFieldAttrs{.{ .@"align" = @alignOf(maybe_message) }};
                    enum_values = enum_values ++ [_]u32{next_value};
                    next_value += 1;
                }
            },
            else => {},
        }
    }

    if (field_names.len == 0) return null;

    const backing_enum = @Enum(u32, .exhaustive, field_names, @ptrCast(enum_values));
    return @Union(.auto, backing_enum, field_names, @ptrCast(union_types.ptr), @ptrCast(union_attrs.ptr));
}
