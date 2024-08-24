## Forking

Values needed for the `anvil_reset` request.

### Properties

```zig
struct {
  jsonRpcUrl: []const u8
  blockNumber: ?u64 = null
}
```

## Reset

Struct representation of a `anvil_reset` request.

### Properties

```zig
struct {
  forking: Forking
}
```

## AnvilRequest
Similar to Ethereum RPC Request but only for `AnvilMethods`.

### Signature

```zig
pub fn AnvilRequest(comptime T: type) type
```

## AnvilMethods

Set of methods implemented by this client for use with anvil.

### Properties

```zig
enum {
  anvil_setBalance
  anvil_setCode
  anvil_setChainId
  anvil_setNonce
  anvil_setNextBlockBaseFeePerGas
  anvil_setMinGasPrice
  anvil_dropTransaction
  anvil_mine
  anvil_reset
  anvil_impersonateAccount
  anvil_stopImpersonatingAccount
  anvil_setRpcUrl
}
```

## AnvilStartOptions

All startup options for starting an anvil proccess.\
All `null` or `false` will not be emitted if you use `parseToArgumentsSlice`

### Properties

```zig
struct {
  /// Number of accounts to start anvil with
  accounts: ?u8 = null
  /// Enable autoImpersonate on start up.
  @"auto-impersonate": bool = false
  /// Block time in seconds for interval mining.
  @"block-time": ?u64 = null
  /// Choose the EVM hardfork to use.
  hardfork: ?SpecId = null
  /// The path to initialize the `genesis.json` file.
  init: ?[]const u8 = null
  /// BIP39 mnemonic phrase used to generate accounts.
  mnemonic: ?[]const u8 = null
  /// Disable auto and interval mining.
  @"no-mining": bool = false
  /// The order were the transactions are ordered in the mempool.
  order: ?enum { fifo, fees } = null
  /// The port number to listen on.
  port: ?u16 = null
  /// Enables steps tracing for debug calls. Returns geth style traces.
  @"steps-tracing": bool = false
  /// Starts the IPC endpoint at a given path.
  ipc: ?[]const u8 = null
  /// Don't send messages to stdout on startup.
  silent: bool = false
  /// Set the timestamp of the genesis block.
  timestamp: ?u64 = null
  /// Disable deploying the default `CREATE2` factory when running anvil without forking.
  @"disable-default-create2-deployer": bool = false
  /// Fetch state over a remote endpoint instead of starting from an empty state.
  @"fork-url": ?[]const u8 = null
  /// Fetch state from a specific block number over a remote endpoint. This is dependent of passing `fork-url`.
  @"fork-block-number": ?u64 = null
  /// Initial retry backoff on encountering errors.
  @"fork-retry-backoff": ?u64 = null
  /// Number of retries per request for spurious networks.
  retries: bool = false
  /// Timeout in ms for requests sent to the remote JSON-RPC server in forking mode.
  timeout: ?u64 = null
  /// Sets the number of assumed available compute units per second for this provider.
  @"compute-units-per-second": ?u64 = null
  /// Disables rate limiting for this node’s provider. Will always override --compute-units-per-second if present.
  @"no-rate-limit": bool = false
  /// Disables RPC caching; all storage slots are read from the endpoint. This flag overrides the project’s configuration file
  @"no-storage-cache": bool = false
  /// The base fee in a block
  @"base-fee": ?u64 = null
  /// The chain ID
  @"chain-id": ?u64 = null
  /// EIP-170: Contract code size limit in bytes. Useful to increase for tests.
  @"code-size-limit": ?u64 = null
  /// The block gas limit
  @"gas-limit": ?u64 = null
  /// The gas price
  @"gas-price": ?u64 = null
  /// Set the CORS `allow_origin`
  @"allow-origin": ?[]const u8 = null
  /// Disable CORS
  @"no-cors": bool = false
  /// The IP address server will listen on.
  host: ?[]const u8 = null
  /// Writes output of `anvil` as json to use specified file.
  @"config-out": ?[]const u8 = null
  /// Dont keep full chain history.
  @"prune-history": bool = false
}
```

### ParseToArgumentsSlice
Converts `self` into a list of slices that will be used by the `anvil process.`
If `self` is set with default value only the `anvil` command will be set in the list.

### Signature

```zig
pub fn parseToArgumentsSlice(self: AnvilStartOptions, allocator: Allocator) ![]const []const u8
```

## InitOptions

Set of inital options to start the http client.

### Properties

```zig
struct {
  /// Allocator to use to create the ChildProcess and other allocations
  allocator: Allocator
  /// The port to use in anvil
  port: u16 = 6969
}
```

## InitClient
Inits the client but doesn't start a seperate process.\
Use this if you already have an `anvil` instance running

### Signature

```zig
pub fn initClient(self: *Anvil, options: InitOptions) void
```

## InitProcess
Start the `anvil` as a child process. The arguments list will be created based on
`AnvilStartOptions`. This will need to allocate memory since it will create the list.\
If `options` are set to their default value it will only start with `anvil` and no arguments.

### Signature

```zig
pub fn initProcess(allocator: Allocator, options: AnvilStartOptions) !Child
```

## Deinit
Cleans up the http client

### Signature

```zig
pub fn deinit(self: *Anvil) void
```

## SetBalance
Sets the balance of a anvil account

### Signature

```zig
pub fn setBalance(self: *Anvil, address: Address, balance: u256) !void
```

## SetCode
Changes the contract code of a address.

### Signature

```zig
pub fn setCode(self: *Anvil, address: Address, code: Hex) !void
```

## SetRpcUrl
Changes the rpc of the anvil connection

### Signature

```zig
pub fn setRpcUrl(self: *Anvil, rpc_url: []const u8) !void
```

## SetCoinbase
Changes the coinbase address

### Signature

```zig
pub fn setCoinbase(self: *Anvil, address: Address) !void
```

## SetLoggingEnable
Enable anvil verbose logging for anvil.

### Signature

```zig
pub fn setLoggingEnable(self: *Anvil) !void
```

## SetMinGasPrice
Changes the min gasprice from the anvil fork

### Signature

```zig
pub fn setMinGasPrice(self: *Anvil, new_price: u64) !void
```

## SetNextBlockBaseFeePerGas
Changes the block base fee from the anvil fork

### Signature

```zig
pub fn setNextBlockBaseFeePerGas(self: *Anvil, new_price: u64) !void
```

## SetChainId
Changes the networks chainId

### Signature

```zig
pub fn setChainId(self: *Anvil, new_id: u64) !void
```

## SetNonce
Changes the nonce of a account

### Signature

```zig
pub fn setNonce(self: *Anvil, address: Address, new_nonce: u64) !void
```

## DropTransaction
Drops a pending transaction from the mempool

### Signature

```zig
pub fn dropTransaction(self: *Anvil, tx_hash: Hash) !void
```

## Mine
Mine a pending transaction

### Signature

```zig
pub fn mine(self: *Anvil, amount: u64, time_in_seconds: ?u64) !void
```

## Reset
Reset the fork

### Signature

```zig
pub fn reset(self: *Anvil, reset_config: Reset) !void
```

## ImpersonateAccount
Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.

### Signature

```zig
pub fn impersonateAccount(self: *Anvil, address: Address) !void
```

## StopImpersonatingAccount
Stops impersonating a EOA or contract.

### Signature

```zig
pub fn stopImpersonatingAccount(self: *Anvil, address: Address) !void
```

