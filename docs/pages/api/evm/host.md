## AccountStatus

The current status of an account.

### Properties

```zig
packed struct {  cold: u1 = 0
  self_destructed: u1 = 0
  touched: u1 = 0
  created: u1 = 0
  loaded: u1 = 0
  non_existent: u1 = 0
}
```

## StorageSlot

Representation of the storage of an evm account.

### Properties

```zig
struct {
  original_value: u256
  present_value: u256
  is_cold: bool
}
```

## AccountInfo

Information associated with an evm account.

### Properties

```zig
struct {
  balance: u256
  nonce: u64
  code_hash: Hash
  code: ?Bytecode
}
```

## Account

Representation of an EVM account.

### Properties

```zig
struct {
  info: AccountInfo
  storage: AutoHashMap(u256, StorageSlot)
  status: AccountStatus
}
```

### IsEmpty
### Signature

```zig
pub fn isEmpty(self: Account, spec_id: SpecId) bool
```

## AccountResult

Result for loding and account from state.

### Properties

```zig
struct {
  is_cold: bool
  is_new_account: bool
}
```

## SStoreResult

Result of a sstore of code.

### Properties

```zig
struct {
  original_value: u256
  present_value: u256
  new_value: u256
  is_cold: bool
}
```

## SelfDestructResult

Result of a self destruct opcode

### Properties

```zig
struct {
  had_value: bool
  target_exists: bool
  is_cold: bool
  previously_destroyed: bool
}
```

## Host

Representation of an EVM context host.

### Properties

```zig
struct {
  ptr: *anyopaque
  vtable: *const VTable
}
```

## VTable

### Properties

```zig
struct {
  /// Gets the balance of an `address` and if that address is cold.
  balance: *const fn (self: *anyopaque, address: Address) ?struct { u256, bool }
  /// Gets the block hash from a given block number
  blockHash: *const fn (self: *anyopaque, block_number: u64) ?Hash
  /// Gets the code of an `address` and if that address is cold.
  code: *const fn (self: *anyopaque, address: Address) ?struct { Bytecode, bool }
  /// Gets the code hash of an `address` and if that address is cold.
  codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool }
  /// Gets the host's `Enviroment`.
  getEnviroment: *const fn (self: *anyopaque) EVMEnviroment
  /// Loads an account.
  loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult
  /// Emits a log owned by an address with the log data.
  log: *const fn (self: *anyopaque, log: Log) anyerror!void
  /// Sets the address to be deleted and any funds it might have to `target` address.
  selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult)
  /// Gets the storage value of an `address` at a given `index` and if that address is cold.
  sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!StateLoaded(u256)
  /// Sets a storage value of an `address` at a given `index` and if that address is cold.
  sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult)
  /// Gets the transient storage value of an `address` at a given `index`.
  tload: *const fn (self: *anyopaque, address: Address, index: u256) ?u256
  /// Sets the transient storage value of an `address` at a given `index`.
  tstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!void
}
```

### Balance
Gets the balance of an `address` and if that address is cold.

### Signature

```zig
pub inline fn balance(self: SelfHost, address: Address) ?struct { u256, bool }
```

### BlockHash
Gets the block hash from a given block number

### Signature

```zig
pub inline fn blockHash(self: SelfHost, block_number: u64) ?Hash
```

### Code
Gets the code of an `address` and if that address is cold.

### Signature

```zig
pub inline fn code(self: SelfHost, address: Address) ?struct { Bytecode, bool }
```

### CodeHash
Gets the code hash of an `address` and if that address is cold.

### Signature

```zig
pub inline fn codeHash(self: SelfHost, address: Address) ?struct { Hash, bool }
```

### GetEnviroment
Gets the code hash of an `address` and if that address is cold.

### Signature

```zig
pub inline fn getEnviroment(self: SelfHost) EVMEnviroment
```

### LoadAccount
Loads an account.

### Signature

```zig
pub inline fn loadAccount(self: SelfHost, address: Address) ?AccountResult
```

### Log
Emits a log owned by an address with the log data.

### Signature

```zig
pub inline fn log(self: SelfHost, log_event: Log) anyerror!void
```

### SelfDestruct
Sets the address to be deleted and any funds it might have to `target` address.

### Signature

```zig
pub inline fn selfDestruct(self: SelfHost, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult)
```

### Sload
Gets the storage value of an `address` at a given `index` and if that address is cold.

### Signature

```zig
pub inline fn sload(self: SelfHost, address: Address, index: u256) anyerror!StateLoaded(u256)
```

### Sstore
Sets a storage value of an `address` at a given `index` and if that address is cold.

### Signature

```zig
pub inline fn sstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult)
```

### Tload
Gets the transient storage value of an `address` at a given `index`.

### Signature

```zig
pub inline fn tload(self: SelfHost, address: Address, index: u256) ?u256
```

### Tstore
Emits a log owned by an address with the log data.

### Signature

```zig
pub inline fn tstore(self: SelfHost, address: Address, index: u256, value: u256) anyerror!void
```

## VTable

### Properties

```zig
struct {
  /// Gets the balance of an `address` and if that address is cold.
  balance: *const fn (self: *anyopaque, address: Address) ?struct { u256, bool }
  /// Gets the block hash from a given block number
  blockHash: *const fn (self: *anyopaque, block_number: u64) ?Hash
  /// Gets the code of an `address` and if that address is cold.
  code: *const fn (self: *anyopaque, address: Address) ?struct { Bytecode, bool }
  /// Gets the code hash of an `address` and if that address is cold.
  codeHash: *const fn (self: *anyopaque, address: Address) ?struct { Hash, bool }
  /// Gets the host's `Enviroment`.
  getEnviroment: *const fn (self: *anyopaque) EVMEnviroment
  /// Loads an account.
  loadAccount: *const fn (self: *anyopaque, address: Address) ?AccountResult
  /// Emits a log owned by an address with the log data.
  log: *const fn (self: *anyopaque, log: Log) anyerror!void
  /// Sets the address to be deleted and any funds it might have to `target` address.
  selfDestruct: *const fn (self: *anyopaque, address: Address, target: Address) anyerror!StateLoaded(SelfDestructResult)
  /// Gets the storage value of an `address` at a given `index` and if that address is cold.
  sload: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!StateLoaded(u256)
  /// Sets a storage value of an `address` at a given `index` and if that address is cold.
  sstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!StateLoaded(SStoreResult)
  /// Gets the transient storage value of an `address` at a given `index`.
  tload: *const fn (self: *anyopaque, address: Address, index: u256) ?u256
  /// Sets the transient storage value of an `address` at a given `index`.
  tstore: *const fn (self: *anyopaque, address: Address, index: u256, value: u256) anyerror!void
}
```

## PlainHost

Mainly serves as a basic implementation of an evm host.

### Properties

```zig
struct {
  /// The EVM enviroment
  env: EVMEnviroment
  /// The storage of this host.
  storage: Storage
  /// The transient storage of this host.
  transient_storage: Storage
  /// The logs of this host.
  log_storage: ArrayList(Log)
}
```

### Init
Creates instance of this `PlainHost`.

### Signature

```zig
pub fn init(self: *Self, allocator: Allocator) void
```

### Deinit
### Signature

```zig
pub fn deinit(self: *Self) void
```

### Host
Returns the `Host` implementation for this instance.

### Signature

```zig
pub fn host(self: *Self) Host
```

## JournaledHost

EVM Journaled context.

### Properties

```zig
struct {
  /// Inner evm state.
  journal: JournaledState
  /// EVM enviroment context.
  env: EVMEnviroment
}
```

### Init
Sets the initial state the journaled host.

### Signature

```zig
pub fn init(enviroment: EVMEnviroment, journal_db: JournaledState) !void
```

### Host
Returns the `Host` implementation for this instance.

### Signature

```zig
pub fn host(self: *Self) Host
```

### Balance
### Signature

```zig
pub fn balance(ctx: *anyopaque, address: Address) ?struct { u256, bool }
```

### BlockHash
### Signature

```zig
pub fn blockHash(ctx: *anyopaque, number: u64) ?Hash
```

### Code
### Signature

```zig
pub fn code(ctx: *anyopaque, address: Address) ?struct { Bytecode, bool }
```

### CodeHash
### Signature

```zig
pub fn codeHash(ctx: *anyopaque, address: Address) ?struct { Hash, bool }
```

### GetEnviroment
### Signature

```zig
pub fn getEnviroment(ctx: *anyopaque) EVMEnviroment
```

### LoadAccount
### Signature

```zig
pub fn loadAccount(ctx: *anyopaque, address: Address) ?AccountResult
```

### Log
### Signature

```zig
pub fn log(ctx: *anyopaque, log_event: Log) !void
```

### SelfDestruct
### Signature

```zig
pub fn selfDestruct(ctx: *anyopaque, from: Address, target: Address) !StateLoaded(SelfDestructResult)
```

### Sload
### Signature

```zig
pub fn sload(ctx: *anyopaque, address: Address, index: u256) !StateLoaded(u256)
```

### Sstore
### Signature

```zig
pub fn sstore(ctx: *anyopaque, address: Address, index: u256, value: u256) !StateLoaded(SStoreResult)
```

### Tload
### Signature

```zig
pub fn tload(ctx: *anyopaque, address: Address, index: u256) ?u256
```

### Tstore
### Signature

```zig
pub fn tstore(ctx: *anyopaque, address: Address, index: u256, value: u256) Allocator.Error!void
```

