const abi = @import("../../abi/abi.zig");
const abi_parameter = @import("../../abi/abi_parameter.zig");

const AbiParameter = abi_parameter.AbiParameter;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const Function = abi.Function;

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
/// Abi representation of the gas price oracle `getL1GasUsed` function
pub const get_l1_gas_func: Function = .{
    .type = .function,
    .name = "getL1GasUsed",
    .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
};
// Abi representation of the gas price oracle `getL1Fee` function
pub const get_l1_fee: Function = .{
    .type = .function,
    .name = "getL1Fee",
    .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
};

pub const transaction_deposited_event_args: []const AbiEventParameter = &.{
    .{ .type = .{ .address = {} }, .name = "from", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "to", .indexed = true },
    .{ .type = .{ .uint = 256 }, .name = "version", .indexed = true },
};

pub const transaction_deposited_event_data: []const AbiParameter = &.{
    .{ .type = .{ .bytes = {} }, .name = "opaqueData" },
};
