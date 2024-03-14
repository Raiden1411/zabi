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

// Abi representation of the gas price oracle `getL2Output` function
pub const get_l2_output_func: Function = .{
    .type = .function,
    .name = "getL2Output",
    .inputs = &.{.{ .type = .{ .uint = 256 }, .name = "_l2OutputIndex" }},
    .stateMutability = .view,
    .outputs = &.{
        .{
            .type = .{ .tuple = {} },
            .name = "",
            .components = &.{
                .{ .type = .{ .fixedBytes = 32 }, .name = "outputRoot" },
                .{ .type = .{ .uint = 128 }, .name = "timestamp" },
                .{ .type = .{ .uint = 128 }, .name = "l2BlockNumber" },
            },
        },
    },
};
// Abi representation of the gas price oracle `getL2Output` function
pub const get_proven_withdrawal: Function = .{
    .type = .function,
    .name = "provenWithdrawals",
    .inputs = &.{.{ .type = .{ .fixedBytes = 32 }, .name = "" }},
    .stateMutability = .view,
    .outputs = &.{
        .{
            .type = .{ .tuple = {} },
            .name = "",
            .components = &.{
                .{ .type = .{ .fixedBytes = 32 }, .name = "outputRoot" },
                .{ .type = .{ .uint = 128 }, .name = "timestamp" },
                .{ .type = .{ .uint = 128 }, .name = "l2OutputIndex" },
            },
        },
    },
};

// Abi representation of the gas price oracle `getL1GasUsed` function
pub const get_l2_index_func: Function = .{
    .type = .function,
    .name = "getL2OutputIndexAfter",
    .inputs = &.{
        .{ .type = .{ .uint = 256 }, .name = "_l2BlockNumber" },
    },
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
};

// Abi representation of the gas price oracle `getL1GasUsed` function
pub const get_finalized_withdrawl: Function = .{
    .type = .function,
    .name = "finalizedWithdrawals",
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "" },
    },
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
};

// Abi representation of the gas price oracle `getL1Fee` function
pub const initiate_withdrawal: Function = .{
    .type = .function,
    .name = "initiateWithdrawal",
    .inputs = &.{
        .{ .type = .{ .address = {} }, .name = "_target" },
        .{ .type = .{ .uint = 256 }, .name = "_gasLimit" },
        .{ .type = .{ .bytes = {} }, .name = "_data" },
    },
    .stateMutability = .payable,
    .outputs = &.{},
};
