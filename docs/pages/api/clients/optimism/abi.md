## message_passed_indexed_params

Indexed arguments of the `MessagePassed` event

```zig
&.{
    .{ .type = .{ .uint = 256 }, .name = "nonce", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "sender", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "target", .indexed = true },
}
```

## message_passed_params

Non indexed arguments of the `MessagePassed` event

```zig
&.{
    .{ .type = .{ .uint = 256 }, .name = "value" },
    .{ .type = .{ .uint = 256 }, .name = "gasLimit" },
    .{ .type = .{ .bytes = {} }, .name = "data" },
    .{ .type = .{ .fixedBytes = 32 }, .name = "withdrawalHash" },
}
```

## get_l1_gas_func

Abi representation of the gas price oracle `getL1GasUsed` function

```zig
.{
    .type = .function,
    .name = "getL1GasUsed",
    .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
}
```

## get_l1_fee

Abi representation of the gas price oracle `getL1Fee` function

```zig
.{
    .type = .function,
    .name = "getL1Fee",
    .inputs = &.{.{ .type = .{ .bytes = {} }, .name = "_data" }},
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
}
```

## transaction_deposited_event_args

Indexed arguments of the `TransactionDeposited` event

```zig
&.{
    .{ .type = .{ .address = {} }, .name = "from", .indexed = true },
    .{ .type = .{ .address = {} }, .name = "to", .indexed = true },
    .{ .type = .{ .uint = 256 }, .name = "version", .indexed = true },
}
```

## transaction_deposited_event_data

Non indexed arguments of the `TransactionDeposited` event

```zig
&.{
    .{ .type = .{ .bytes = {} }, .name = "opaqueData" },
}
```

## get_l2_output_func

```zig
.{
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
}
```

## get_proven_withdrawal

Abi representation of the gas price oracle `provenWithdrawals` function

```zig
.{
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
}
```

## get_l2_index_func

Abi representation of the gas price oracle `getL2OutputIndexAfter` function

```zig
.{
    .type = .function,
    .name = "getL2OutputIndexAfter",
    .inputs = &.{
        .{ .type = .{ .uint = 256 }, .name = "_l2BlockNumber" },
    },
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
}
```

## get_finalized_withdrawal

Abi representation of the gas price oracle `finalizedWithdrawals` function

```zig
.{
    .type = .function,
    .name = "finalizedWithdrawals",
    .inputs = &.{
        .{ .type = .{ .fixedBytes = 32 }, .name = "" },
    },
    .stateMutability = .view,
    // Not the real outputs represented in the ABI but here we don't really care for it.
    // The ABI returns a uint256 but we can just `parseInt` it
    .outputs = &.{},
}
```

## initiate_withdrawal

Abi representation of the gas price oracle `initiateWithdrawal` function

```zig
.{
    .type = .function,
    .name = "initiateWithdrawal",
    .inputs = &.{
        .{ .type = .{ .address = {} }, .name = "_target" },
        .{ .type = .{ .uint = 256 }, .name = "_gasLimit" },
        .{ .type = .{ .bytes = {} }, .name = "_data" },
    },
    .stateMutability = .payable,
    .outputs = &.{},
}
```

## deposit_transaction

Abi representation of the gas price oracle `depositTransaction` function

```zig
.{
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
}
```

## finalize_withdrawal

Abi representation of the gas price oracle `finalizeWithdrawalTransaction` function

```zig
.{
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
}
```

## prove_withdrawal

Abi representation of the gas price oracle `proveWithdrawalTransaction` function

```zig
.{
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
}
```

## find_latest_games

Abi representation of the dispute game factory `findLastestGames` function

```zig
.{
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
}
```

