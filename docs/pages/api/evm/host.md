## Host

Representation of an EVM context host.

### Properties

```zig
```

## VTable

## Balance
Gets the balance of an `address` and if that address is cold.

### Signature

```zig
pub inline fn balance(self: SelfHost, address: Address) ?struct { u256, bool }
```

## BlockHash
Gets the block hash from a given block number

### Signature

```zig
pub inline fn blockHash(self: SelfHost, block_number: u256) ?Hash
```

## Code
Gets the code of an `address` and if that address is cold.

### Signature

```zig
pub inline fn code(self: SelfHost, address: Address) ?struct { Bytecode, bool }
```

## CodeHash
Gets the code hash of an `address` and if that address is cold.

### Signature

```zig
pub inline fn codeHash(self: SelfHost, address: Address) ?struct { Hash, bool }
```

## GetEnviroment
Gets the code hash of an `address` and if that address is cold.

### Signature

```zig
pub inline fn getEnviroment(self: SelfHost) EVMEnviroment
```

## LoadAccount
Loads an account.

### Signature

```zig
pub inline fn loadAccount(self: SelfHost, address: Address) ?AccountResult
```

## Log
Emits a log owned by an address with the log data.

### Signature

```zig
pub inline fn log(self: SelfHost, log_event: Log) anyerror!void
```

## SelfDestruct
Sets the address to be deleted and any funds it might have to `target` address.

### Signature

```zig
pub inline fn selfDestruct(self: SelfHost, address: Address, target: Address) anyerror!SelfDestructResult
```

## Sload
Gets the storage value of an `address` at a given `index` and if that address is cold.

### Signature

```zig
pub inline fn sload(self: SelfHost, address: Address, index: u256) anyerror!struct { u256, bool }
```

## Sstore
Sets a storage value of an `address` at a given `index` and if that address is cold.

### Signature

```zig
pub inline fn sstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!SStoreResult
```

## Tload
Gets the transient storage value of an `address` at a given `index`.

### Signature

```zig
pub inline fn tload(self: SelfHost, address: Address, index: u256) ?u256
```

## Tstore
Emits a log owned by an address with the log data.

### Signature

```zig
pub inline fn tstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!void
```

## AccountResult

Result for loding and account from state.

## SStoreResult

Result of a sstore of code.

## SelfDestructResult

Result of a self destruct opcode

## PlainHost

Mainly serves as a basic implementation of an evm host.

### Properties

```zig
```

## Init
Creates instance of this `PlainHost`.

### Signature

```zig
pub fn init(self: *Self, allocator: Allocator) void
```

## Deinit
### Signature

```zig
pub fn deinit(self: *Self) void
```

## Host
Returns the `Host` implementation for this instance.

### Signature

```zig
pub fn host(self: *Self) Host
```

