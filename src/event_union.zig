const Type = @import("std").builtin.Type;

pub fn EventUnion(comptime protocols: anytype) type {
    var backing_enum = Type.Enum{
        .decls = &.{},
        .fields = &.{},
        .is_exhaustive = true,
        .tag_type = usize,
    };

    var event_union = Type.Union{
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
            const InterfaceEvent = InterfaceEventUnion(interface);
            event_union.fields = event_union.fields ++ [_]Type.UnionField{.{
                .alignment = @alignOf(InterfaceEvent),
                .name = interface.interface,
                .type = InterfaceEvent,
            }};
            backing_enum.fields = backing_enum.fields ++ [_]Type.EnumField{.{
                .name = interface.interface,
                .value = next_value,
            }};
            next_value += 1;
        }
    }

    event_union.tag_type = @Type(.{ .@"enum" = backing_enum });
    return @Type(.{ .@"union" = event_union });
}

fn InterfaceEventUnion(comptime Interface: type) type {
    var event_union = Type.Union{
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
    inline for (@typeInfo(Interface).@"enum".decls) |maybe_event_decl| {
        const maybe_event = @field(Interface, maybe_event_decl.name);
        switch (@typeInfo(@TypeOf(maybe_event))) {
            .type => {
                if (@hasDecl(maybe_event, "_name") and
                    @hasDecl(maybe_event, "_signature") and
                    @hasDecl(maybe_event, "_opcode"))
                {
                    event_union.fields = event_union.fields ++ [_]Type.UnionField{.{
                        .alignment = @alignOf(maybe_event),
                        .name = @field(maybe_event, "_name"),
                        .type = maybe_event,
                    }};
                    backing_enum.fields = backing_enum.fields ++ [_]Type.EnumField{.{
                        .name = @field(maybe_event, "_name"),
                        .value = next_value,
                    }};
                    next_value += 1;
                }
            },
            else => {},
        }
    }

    backing_enum.tag_type = @Type(.{ .@"enum" = backing_enum });
    return @Type(.{ .@"union" = event_union });
}
