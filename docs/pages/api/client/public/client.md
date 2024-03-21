# Public Clients

## Definition

Zabi provides a http and websocket client that can be used to interact with the json rpc endpoint.
Currently it supports around 95% of all available RPC method with the goal of reaching 100%. 

The http and websocket client do not mirror 100% in terms of their methods. So depending on what you want to achieve you can use one or the other.

The websocket client will run the read loop in a seperate thread. Both of these clients support debug logging for you to better understand possible errors in case they happen.

RPC request will return an `RPCResponse` type that is essentially a json parsed value. The caller now owns the memory and it no longer the job of the rpc client to manage that memory.
You can still use an `ArenaAllocator` if you want to mimic the previous behaviour or use a previous version of zabi.

Zabi also support custom client for the op-stack that follow this same principle.

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

The client json parse all messages that the RPC client sends. So you will only interact with the `result` values of the RPC response. \
This also includes the error messages. In those case they will be converted to zig errors that can be handled.

## Example

:::code-group

```zig [http.zig]
const uri = try std.Uri.parse("http://localhost:8545/");
var client: PubClient = undefined;
defer client.deinit();
try client.init(.{ .allocator = std.testing.allocator, .uri = uri });

const block_req = try pub_client.getBlockNumber();
defer block_req.deinit();
```

```zig [websocket.zig]
const uri = try std.Uri.parse("http://localhost:8545/");
var ws_client: WebSocketHandler = undefined;
defer ws_client.deinit();
try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

const block_req = try ws_client.getBlockNumber();`
defer block_req.deinit();
```

:::

You can take look at our current tests to have a better grasp on using the clients.

For the websocket client start [here](https://github.com/Raiden1411/zabi/blob/94d42c13b4a628c407827a765f03157de7c3dff1/src/WebSocket.zig#L1693) \
For the http client start [here](https://github.com/Raiden1411/zabi/blob/94d42c13b4a628c407827a765f03157de7c3dff1/src/Client.zig#L888)
