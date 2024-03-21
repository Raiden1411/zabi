# OP Stack clients

## Definition

Zabi supports the OP stack contracts and has custom clients that you can use to interact with them.
It also has custom wallet clients to interact directly with the contracts.

## Usage

Depending on the type of client you want to init a set of seperate options are available.

### Http client

```zig
const InitOptions = struct {
    /// Allocator used to manage the memory arena.
    allocator: Allocator,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// The interval to retry the request. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// Retry count for failed requests.
    retries: u8 = 5,
    /// Fork url for anvil to fork from
    uri: std.Uri,
};
```

### Websocket Client

```zig
const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// Fork url for anvil to fork from
    uri: std.Uri,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: EthereumEvents) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
    retries: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
};
```

By default the contracts that it uses are from OP but if you have other contracts from other chains that support the superchain you can use those.

## Example RPC client

```zig 
const uri = try std.Uri.parse("http://localhost:8545/");

var op: L1Client(.http) = undefined;
defer op.deinit();

try op.init(.{ .uri = uri, .allocator = testing.allocator }, null);

const l2_output = try op.getL2Output(2725977);

try testing.expectEqual(l2_output.timestamp, 1686075935);
try testing.expectEqual(l2_output.outputIndex, 0);
try testing.expectEqual(l2_output.l2BlockNumber, 105236863);
```

## Example Wallet client

```zig 
var wallet_op: L2WalletClient(.http) = undefined;
defer wallet_op.deinit();

const uri = try std.Uri.parse("http://localhost:8544/");
try wallet_op.init("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{
    .allocator = testing.allocator,
    .uri = uri,
    .chain_id = .op_mainnet,
}, null);

const final = try wallet_op.finalizeWithdrawal(.{
    .data = @constCast(&[_]u8{0x01}),
    .sender = try utils.addressToBytes("0x02f086dBC384d69b3041BC738F0a8af5e49dA181"),
    .target = try utils.addressToBytes("0x02f086dBC384d69b3041BC738F0a8af5e49dA181"),
    .value = 335000000000000000000,
    .gasLimit = 100000,
    .nonce = 1766847064778384329583297500742918515827483896875618958121606201292641795,
});
defer final.deinit();
```
