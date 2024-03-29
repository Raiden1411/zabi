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
const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
const uri = try std.Uri.parse("http://localhost:8545/");

var contract: Contract(.http) = undefined;
defer contract.deinit();

try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

const ReturnType = std.meta.Tuple(&[_]type{[]const u8});
const result = try contract.readContractFunction(ReturnType, "ownerOf", .{69}, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5", .from = try contract.wallet.getWalletAddress() } });
```

```zig [comptime.zig]
const abi = &.{.{ .abiFunction = .{ .type = .function, .inputs = &.{ .{ .type = .{ .address = {} }, .name = "operator" }, .{ .type = .{ .bool = {} }, .name = "approved" } }, .stateMutability = .nonpayable, .outputs = &.{}, .name = "setApprovalForAll" } }};
const uri = try std.Uri.parse("http://localhost:8545/");

var contract: ContractComptime(.http) = undefined;
defer contract.deinit();

try contract.init(.{ .abi = abi, .private_key = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .wallet_opts = .{ .allocator = testing.allocator, .uri = uri } });

const result = try contract.readContractFunction("ownerOf", .{69}, .{ .eip1559 = .{ .to = "0x5Af0D9827E0c53E4799BB226655A1de152A425a5", .from = try contract.wallet.getWalletAddress() } });
```

:::
