# Wallet Client

## Definition

Zabi also exposes a wallet client implementation that is essentially a merge of the underlaying methods of a http or websocket client with the `Signer`.

All of methods RPC methods can be accessed under `pub_client`. \
This also applies for the signer and the `signer` property.

The wallet implementation supports signing of `EIP712` type messages as well as normal messages. This also includes verifying both set of messages.
With this client you will also be able to send transactions to the network. You wont need to know every transaction detail and you can let the wallet prepare, assert it's correctness and then send the transaction to the network.

The wallet client also supports waiting for the transaction to be mined via `waitForTransactionReceipt`.

In a future release it's expected that you will be able to pool prepared transacitions so that you can leave them in memory and the client can use them.

## Usage

Much like the public clients depending on which type of client you want to have on the wallet a set of different init options will be available. Have a look [here](/api/client/public/client#http-client) to find out more.
You will also need a private key or you can pass in `null` and it generate a key for you.

```zig
const uri = try std.Uri.parse("http://localhost:8545/");
var wallet: Wallet(.http) = undefined;

var buffer: [32]u8 = undefined;
_ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

try wallet.init(buffer, .{ .allocator = testing.allocator, .uri = uri });
defer wallet.deinit();

var tx: transaction.PrepareEnvelope = .{ .eip1559 = undefined };
tx.eip1559.type = 2;
tx.eip1559.value = try utils.parseEth(1);
tx.eip1559.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

const tx_hash = try wallet.sendTransaction(tx);
const receipt = try wallet.waitForTransactionReceipt(tx_hash, 1)
```
