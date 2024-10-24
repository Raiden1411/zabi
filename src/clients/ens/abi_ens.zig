const Function = @import("zabi-abi").abitypes.Function;

pub const addr_resolver: Function = .{
    .name = "addr",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "name" },
    },
    .outputs = &.{
        .{ .type = .{ .address = {} }, .name = "" },
    },
};

pub const resolver: Function = .{
    .name = "resolve",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "name" },
        .{ .type = .{ .bytes = {} }, .name = "data" },
    },
    .outputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "" },
        .{ .type = .{ .address = {} }, .name = "address" },
    },
};

pub const text_resolver: Function = .{
    .name = "text",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "name" },
        .{ .type = .{ .string = {} }, .name = "key" },
    },
    .outputs = &.{
        .{ .type = .{ .string = {} }, .name = "" },
    },
};

pub const find_resolver: Function = .{
    .name = "findResolver",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "" },
    },
    .outputs = &.{
        .{ .type = .{ .address = {} }, .name = "" },
        .{ .type = .{ .fixedBytes = 32 }, .name = "" },
    },
};

pub const reverse_resolver: Function = .{
    .name = "reverse",
    .type = .function,
    .stateMutability = .view,
    .inputs = &.{
        .{ .type = .{ .bytes = {} }, .name = "reverseName" },
    },
    .outputs = &.{
        .{ .type = .{ .string = {} }, .name = "resolvedName" },
        .{ .type = .{ .address = {} }, .name = "resolvedAddress" },
        .{ .type = .{ .address = {} }, .name = "reverseResolver" },
        .{ .type = .{ .address = {} }, .name = "resolver" },
    },
};
