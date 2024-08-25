const abi = @import("../../abi/abi.zig");
const abi_parameter = @import("../../abi/abi_parameter.zig");

const AbiParameter = abi_parameter.AbiParameter;
const AbiEventParameter = abi_parameter.AbiEventParameter;
const Function = abi.Function;

/// Indexed arguments of the `MessagePassed` event
pub const message_passed_indexed_params: []const AbiEventParameter = &.{
    .{ .type = .{ .uint = 256 }, .name = "nonce", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "sender", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "target", .indexed = true },
};
/// Non indexed arguments of the `MessagePassed` event
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
/// Abi representation of the gas price oracle `getL1Fee` function
pub const get_l1_fee: Function = .{
    .type = .function,
    .name = "getL1Fee",
    .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
};
/// Indexed arguments of the `TransactionDeposited` event
pub const transaction_deposited_event_args: []const AbiEventParameter = &.{
    .{ .type = .{ .address = {} }, .name = "from", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "to", .indexed = true },
    .{ .type = .{ .uint = 256 }, .name = "version", .indexed = true },
};
/// Non indexed arguments of the `TransactionDeposited` event
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
/// Abi representation of the gas price oracle `provenWithdrawals` function
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
/// Abi representation of the gas price oracle `getL2OutputIndexAfter` function
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
/// Abi representation of the gas price oracle `finalizedWithdrawals` function
pub const get_finalized_withdrawal: Function = .{
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
/// Abi representation of the gas price oracle `initiateWithdrawal` function
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
/// Abi representation of the gas price oracle `depositTransaction` function
pub const deposit_transaction: Function = .{
    .type = .function,
    .name = "depositTransaction",
    .inputs = &.{
        .{ .type = .{ .address = {} }, .name = "_to" },
        .{ .type = .{ .uint = 256 }, .name = "_value" },
        .{ .type = .{ .uint = 64 }, .name = "_gasLimit" },
        .{ .type = .{ .bool = {} }, .name = "_isCreation" },
        .{ .type = .{ .bytes = {} }, .name = "_data" },
    },
    .stateMutability = .payable,
    .outputs = &.{},
};
/// Abi representation of the gas price oracle `finalizeWithdrawalTransaction` function
pub const finalize_withdrawal: Function = .{
    .type = .function,
    .name = "finalizeWithdrawalTransaction",
    .inputs = &.{
        .{
            .type = .{ .tuple = {} },
            .name = "_tx",
            .components = &.{
                .{ .type = .{ .uint = 256 }, .name = "nonce" },
                .{ .type = .{ .address = {} }, .name = "sender" },
                .{ .type = .{ .address = {} }, .name = "target" },
                .{ .type = .{ .uint = 256 }, .name = "value" },
                .{ .type = .{ .uint = 256 }, .name = "gasLimit" },
                .{ .type = .{ .bytes = {} }, .name = "data" },
            },
        },
    },
    .stateMutability = .nonpayable,
    .outputs = &.{},
};
/// Abi representation of the gas price oracle `proveWithdrawalTransaction` function
pub const prove_withdrawal: Function = .{
    .type = .function,
    .name = "proveWithdrawalTransaction",
    .inputs = &.{
        .{
            .type = .{ .tuple = {} },
            .name = "_tx",
            .components = &.{
                .{ .type = .{ .uint = 256 }, .name = "nonce" },
                .{ .type = .{ .address = {} }, .name = "sender" },
                .{ .type = .{ .address = {} }, .name = "target" },
                .{ .type = .{ .uint = 256 }, .name = "value" },
                .{ .type = .{ .uint = 256 }, .name = "gasLimit" },
                .{ .type = .{ .bytes = {} }, .name = "data" },
            },
        },
        .{ .type = .{ .uint = 256 }, .name = "_l2OutputIndex" },
        .{
            .type = .{ .tuple = {} },
            .name = "_outputRootProof",
            .components = &.{
                .{ .type = .{ .fixedBytes = 32 }, .name = "version" },
                .{ .type = .{ .fixedBytes = 32 }, .name = "stateRoot" },
                .{ .type = .{ .fixedBytes = 32 }, .name = "messagePasserStorageRoot" },
                .{ .type = .{ .fixedBytes = 32 }, .name = "latestBlockhash" },
            },
        },
        .{ .type = .{ .dynamicArray = &.{ .bytes = {} } }, .name = "_withdrawalProof " },
    },
    .stateMutability = .nonpayable,
    .outputs = &.{},
};
/// Abi representation of the dispute game factory `findLastestGames` function
pub const find_latest_games: Function = .{
    .type = .function,
    .name = "findLatestGames",
    .inputs = &.{
        .{ .type = .{ .uint = 32 }, .name = "_gameType" },
        .{ .type = .{ .uint = 256 }, .name = "_start" },
        .{ .type = .{ .uint = 256 }, .name = "_n" },
    },
    .stateMutability = .view,
    .outputs = &.{
        .{
            .type = .{ .dynamicArray = &.{ .tuple = {} } },
            .name = "",
            .components = &.{
                .{ .type = .{ .uint = 256 }, .name = "index" },
                .{ .type = .{ .fixedBytes = 32 }, .name = "metadata" },
                .{ .type = .{ .uint = 64 }, .name = "timestamp" },
                .{ .type = .{ .fixedBytes = 32 }, .name = "rootClaim" },
                .{ .type = .{ .bytes = {} }, .name = "extraData" },
            },
        },
    },
};
