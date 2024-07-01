# Contract Client

## Definition

Zabi also exposes a contract client implementation that is essentially a merge of a wallet client with a contract ABI.

Zabi's contract implementation lets you interact with it in two ways. You can either use a runtime only ABI or a comptime know signatures.
You are able to `Read`, `Write`, `Simulate` and `Deploy` contracts.

All of the wallet's methods can be accessed under the `wallet` property.

For comptime know ABI signatures you will get more explict help from the compiler when it comes to encoding and decoding the RPC responses.

## Usage

Like it was stated above you can use either runtime or comptime know abis. Depending on what you are trying to achieve, you will always need to also init the wallet and you will need to know the init options that the wallet needs. Find out more [here](/api/client/wallet/client)

:::code-group

```zig [runtime.zig]
const abi = &.{
    .{
        .abiFunction = .{
            .type = .function,
            .inputs = &.{
                .{ .type = .{ .address = {} }, .name = "operator" },
                .{ .type = .{ .bool = {} }, .name = "approved" },
            },
            .stateMutability = .nonpayable,
            .outputs = &.{},
            .name = "setApprovalForAll",
        },
    },
};
const uri = try std.Uri.parse("http://localhost:6970/");

var contract: Contract(.websocket) = undefined;
defer contract.deinit();

var buffer: Hash = undefined;
_ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

try contract.init(.{
    .abi = abi,
    .private_key = buffer,
    .wallet_opts = .{ .allocator = testing.allocator, .uri = uri },
});

const result = try contract.simulateWriteCall("setApprovalForAll", .{ try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6546"), true }, .{
    .type = .london,
    .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
});
defer result.deinit();
```

```zig [comptime.zig]
const uri = try std.Uri.parse("http://localhost:6969/");

var contract: ContractComptime(.http) = undefined;
defer contract.deinit();

var buffer: Hash = undefined;
_ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

try contract.init(.{
    .private_key = buffer,
    .wallet_opts = .{ .allocator = testing.allocator, .uri = uri },
});

const result = try contract.simulateWriteCall(.{
    .type = .function,
    .inputs = &.{
        .{ .type = .{ .address = {} }, .name = "operator" },
        .{ .type = .{ .bool = {} }, .name = "approved" },
    },
    .stateMutability = .nonpayable,
    .outputs = &.{},
    .name = "setApprovalForAll",
}, .{ .args = .{
    try utils.addressToBytes("0x19bb64b80CbF61E61965B0E5c2560CC7364c6547"),
    true,
}, .overrides = .{
    .type = .berlin,
    .to = try utils.addressToBytes("0x5Af0D9827E0c53E4799BB226655A1de152A425a5"),
} });
defer result.deinit();
```

:::
