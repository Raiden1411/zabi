## Reset

### Properties

```zig
struct {
  forking: struct {
        jsonRpcUrl: []const u8,
        blockNumber: u64,
    }
}
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## HardhatRequest
### Signature

```zig
pub fn HardhatRequest(comptime T: type) type
```

## HardhatMethods

### Properties

```zig
enum {
  hardhat_setBalance
  hardhat_setCode
  hardhat_setChainId
  hardhat_setNonce
  hardhat_setNextBlockBaseFeePerGas
  hardhat_setMinGasPrice
  hardhat_dropTransaction
  hardhat_mine
  hardhat_reset
  hardhat_impersonateAccount
  hardhat_stopImpersonatingAccount
  hardhat_setRpcUrl
}
```

## StartUpOptions

### Properties

```zig
struct {
  /// Allocator to use to create the ChildProcess and other allocations
  allocator: Allocator
  /// The localhost address.
  localhost: []const u8 = "http://127.0.0.1:8545/"
}
```

## InitClient
### Signature

```zig
pub fn initClient(self: *Hardhat, opts: StartUpOptions) !void
```

## Deinit
Cleans up the http client

### Signature

```zig
pub fn deinit(self: *Hardhat) void
```

## SetBalance
Sets the balance of a hardhat account

### Signature

```zig
pub fn setBalance(self: *Hardhat, address: Address, balance: u256) !void
```

## SetCode
Changes the contract code of a address.

### Signature

```zig
pub fn setCode(self: *Hardhat, address: Address, code: Hex) !void
```

## SetRpcUrl
Changes the rpc of the hardhat connection

### Signature

```zig
pub fn setRpcUrl(self: *Hardhat, rpc_url: []const u8) !void
```

## SetCoinbase
Changes the coinbase address

### Signature

```zig
pub fn setCoinbase(self: *Hardhat, address: Address) !void
```

## SetLoggingEnable
Enable hardhat verbose logging for hardhat.

### Signature

```zig
pub fn setLoggingEnable(self: *Hardhat) !void
```

## SetMinGasPrice
Changes the min gasprice from the hardhat fork

### Signature

```zig
pub fn setMinGasPrice(self: *Hardhat, new_price: u64) !void
```

## SetNextBlockBaseFeePerGas
Changes the next blocks base fee.

### Signature

```zig
pub fn setNextBlockBaseFeePerGas(self: *Hardhat, new_price: u64) !void
```

## SetChainId
Changes the networks chainId

### Signature

```zig
pub fn setChainId(self: *Hardhat, new_id: u64) !void
```

## SetNonce
Changes the nonce of a account

### Signature

```zig
pub fn setNonce(self: *Hardhat, address: []const u8, new_nonce: u64) !void
```

## DropTransaction
Drops a pending transaction from the mempool

### Signature

```zig
pub fn dropTransaction(self: *Hardhat, tx_hash: Hash) !void
```

## Mine
Mine a pending transaction

### Signature

```zig
pub fn mine(self: *Hardhat, amount: u64, time_in_seconds: ?u64) !void
```

## Reset
Reset the fork

### Signature

```zig
pub fn reset(self: *Hardhat, reset_config: ?Reset) !void
```

## ImpersonateAccount
Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.

### Signature

```zig
pub fn impersonateAccount(self: *Hardhat, address: Address) !void
```

## StopImpersonatingAccount
Stops impersonating a EOA or contract.

### Signature

```zig
pub fn stopImpersonatingAccount(self: *Hardhat, address: Address) !void
```

