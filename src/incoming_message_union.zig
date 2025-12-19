const Type = @import("std").builtin.Type;

pub fn IncomingMessageUnion(comptime protocols: anytype) type {
    var backing_enum = Type.Enum{
        .decls = &.{},
        .fields = &.{},
        .is_exhaustive = true,
        .tag_type = usize,
    };

    var message_union = Type.Union{
        .decls = &.{},
        .fields = &.{},
        .layout = .auto,
        .tag_type = null,
    };

    var next_value: usize = 0;
    inline for (@typeInfo(@TypeOf(protocols)).@"struct".fields) |protocol_field| {
        const protocol = @field(protocols, protocol_field.name);
        inline for (@typeInfo(protocol).@"struct".decls) |interface_decl| {
            const interface = @field(protocol, interface_decl.name);
            if (InterfaceMessageUnion(interface)) |InterfaceMessage| {
                message_union.fields = message_union.fields ++ [_]Type.UnionField{.{
                    .alignment = @alignOf(InterfaceMessage),
                    .name = interface.interface,
                    .type = InterfaceMessage,
                }};
                backing_enum.fields = backing_enum.fields ++ [_]Type.EnumField{.{
                    .name = interface.interface,
                    .value = next_value,
                }};
                next_value += 1;
            }
        }
    }

    message_union.tag_type = @Type(.{ .@"enum" = backing_enum });
    return @Type(.{ .@"union" = message_union });
}

fn InterfaceMessageUnion(comptime Interface: type) ?type {
    var message_union = Type.Union{
        .decls = &.{},
        .fields = &.{},
        .layout = .auto,
        .tag_type = null,
    };
    var backing_enum = Type.Enum{
        .decls = &.{},
        .fields = &.{},
        .is_exhaustive = true,
        .tag_type = usize,
    };

    var next_value: usize = 0;
    inline for (@typeInfo(Interface).@"enum".decls) |maybe_message_decl| {
        const maybe_message = @field(Interface, maybe_message_decl.name);
        switch (@typeInfo(@TypeOf(maybe_message))) {
            .type => {
                if (@hasDecl(maybe_message, "_name") and
                    @hasDecl(maybe_message, "_signature") and
                    @hasDecl(maybe_message, "_opcode"))
                {
                    message_union.fields = message_union.fields ++ [_]Type.UnionField{.{
                        .alignment = @alignOf(maybe_message),
                        .name = @field(maybe_message, "_name"),
                        .type = maybe_message,
                    }};
                    backing_enum.fields = backing_enum.fields ++ [_]Type.EnumField{.{
                        .name = @field(maybe_message, "_name"),
                        .value = next_value,
                    }};
                    next_value += 1;
                }
            },
            else => {},
        }
    }

    if (message_union.fields.len == 0) return null;

    message_union.tag_type = @Type(.{ .@"enum" = backing_enum });
    return @Type(.{ .@"union" = message_union });
}
