const abi_parameter = @import("../../abi/abi_parameter.zig");

const AbiParameter = abi_parameter.AbiParameter;
const AbiEventParameter = abi_parameter.AbiEventParameter;

pub const message_passed_indexed_params: []const AbiEventParameter = &.{
    .{ .type = .{ .uint = 256 }, .name = "nonce", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "sender", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "target", .indexed = true },
};

pub const message_passed_params: []const AbiParameter = &.{
    .{ .type = .{ .uint = 256 }, .name = "value" },
    .{ .type = .{ .uint = 256 }, .name = "gasLimit" },
    .{ .type = .{ .bytes = {} }, .name = "data" },
    .{ .type = .{ .fixedBytes = 32 }, .name = "withdrawalHash" },
};
