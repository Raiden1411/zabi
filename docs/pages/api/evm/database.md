## Database

Generic interface for implementing a database.

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
  /// Loads the account information associated to an address.
  basic: *const fn (self: *anyopaque, address: Address) anyerror!?AccountInfo
  /// Gets the block hash from a given block number
  codeByHash: *const fn (self: *anyopaque, code_hash: Hash) anyerror!Bytecode
  /// Gets the code of an `address` and if that address is cold.
  storage: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!u256
  /// Gets the code hash of an `address` and if that address is cold.
  blockHash: *const fn (self: *anyopaque, number: u64) anyerror!Hash
}
```

### Basic
Loads the account information associated to an address.

### Signature

```zig
pub inline fn basic(self: Self, address: Address) anyerror!?AccountInfo
```

### CodeByHash
Gets the block hash from a given block number

### Signature

```zig
pub inline fn codeByHash(self: Self, code_hash: Hash) anyerror!Bytecode
```

### Storage
Gets the code of an `address` and if that address is cold.

### Signature

```zig
pub inline fn storage(self: Self, address: Address, index: u256) anyerror!u256
```

### BlockHash
Gets the code hash of an `address` and if that address is cold.

### Signature

```zig
pub inline fn blockHash(self: Self, number: u64) anyerror!Hash
```

## VTable

### Properties

```zig
struct {
  /// Loads the account information associated to an address.
  basic: *const fn (self: *anyopaque, address: Address) anyerror!?AccountInfo
  /// Gets the block hash from a given block number
  codeByHash: *const fn (self: *anyopaque, code_hash: Hash) anyerror!Bytecode
  /// Gets the code of an `address` and if that address is cold.
  storage: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!u256
  /// Gets the code hash of an `address` and if that address is cold.
  blockHash: *const fn (self: *anyopaque, number: u64) anyerror!Hash
}
```

## AccountState

The state of the database account.

### Properties

```zig
enum {
  not_existing
  touched
  storage_cleared
  none
}
```

## DatabaseAccount

Representation of an account in the database.

### Properties

```zig
struct {
  info: AccountInfo
  account_state: AccountState
  storage: AutoHashMap(u256, u256)
}
```

## MemoryDatabase

A implementation of the `Database` interface.

This stores all changes in memory all clears all changes once a
program exits execution.

### Properties

```zig
struct {
  /// Hashmap of account associated with their addresses.
  account: AutoHashMapUnmanaged(Address, DatabaseAccount)
  /// The allocator that managed any allocated memory.
  allocator: Allocator
  /// Hashmap of block numbers and block_hashes.
  block_hashes: AutoHashMapUnmanaged(u256, Hash)
  /// Hashmap of block_hashes and their associated bytecode.
  contracts: AutoHashMapUnmanaged(Hash, Bytecode)
  /// Inner fallback database.
  db: Database
  /// List of emitted logs.
  logs: ArrayListUnmanaged(Log)
}
```

## AccountLoadError

Set of possible error when loading an account.

```zig
BasicErrors || error{AccountNonExistent}
```

## BasicErrors

Set of possible basic database errors.

```zig
Allocator.Error || error{UnexpectedError}
```

### Init
Sets the initial state of the database.

### Signature

```zig
pub fn init(
    self: *Self,
    allocator: Allocator,
    db: Database,
) Allocator.Error!void
```

### Deinit
Clears any allocated memory by this database
and the storage accounts.

### Signature

```zig
pub fn deinit(self: *Self) void
```

### Database
Returns the implementation of the `Database` interface.

### Signature

```zig
pub fn database(self: *Self) Database
```

### AddContract
Adds the contract code of an account into the `contracts` hashmap.

### Signature

```zig
pub fn addContract(
    self: *Self,
    account: *AccountInfo,
) Allocator.Error!void
```

### AddAccountInfo
Adds the account information to the account associated with the provided address.

### Signature

```zig
pub fn addAccountInfo(
    self: *Self,
    address: Address,
    account: *AccountInfo,
) Allocator.Error!void
```

### AddAccountStorage
Updates the account storage for the given slot index with the provided value.

### Signature

```zig
pub fn addAccountStorage(
    self: *Self,
    address: Address,
    slot: u256,
    value: u256,
) AccountLoadError!void
```

### Basic
Loads the account information from the database.

### Signature

```zig
pub fn basic(
    self: *anyopaque,
    address: Address,
) BasicErrors!?AccountInfo
```

### CodeByHash
Gets the associated bytecode to the provided `code_hash`.

### Signature

```zig
pub fn codeByHash(
    self: *anyopaque,
    code_hash: Hash,
) error{UnexpectedError}!Bytecode
```

### Storage
Get the value in an account's storage slot.

It is assumed that account is already loaded.

### Signature

```zig
pub fn storage(
    self: *anyopaque,
    address: Address,
    index: u256,
) BasicErrors!u256
```

### BlockHash
Gets the associated block_hashes from the provided number.

### Signature

```zig
pub fn blockHash(
    self: *anyopaque,
    number: u64,
) BasicErrors!Hash
```

### Commit
Commits all of the changes to the database.

### Signature

```zig
pub fn commit(
    self: *Self,
    changes: AutoHashMapUnmanaged(Address, Account),
) AccountLoadError!void
```

### UpdateAccountStorage
Updates the storage from a given account.

### Signature

```zig
pub fn updateAccountStorage(
    self: *Self,
    address: Address,
    account_storage: AutoHashMap(u256, u256),
) AccountLoadError!void
```

### LoadAccount
Loads an account from the database.

### Signature

```zig
pub fn loadAccount(
    self: *Self,
    address: Address,
) AccountLoadError!*DatabaseAccount
```

## AccountLoadError

Set of possible error when loading an account.

```zig
BasicErrors || error{AccountNonExistent}
```

## BasicErrors

Set of possible basic database errors.

```zig
Allocator.Error || error{UnexpectedError}
```

## PlainDatabase

Empty database used only for testing.

### Properties

```zig
struct {
  empty: void = {}
}
```

### Basic
### Signature

```zig
pub fn basic(_: *anyopaque, _: Address) !?AccountInfo
```

### CodeByHash
### Signature

```zig
pub fn codeByHash(_: *anyopaque, _: Hash) !Bytecode
```

### Storage
### Signature

```zig
pub fn storage(_: *anyopaque, _: Address, _: u256) !u256
```

### BlockHash
### Signature

```zig
pub fn blockHash(_: *anyopaque, number: u64) !Hash
```

### Database
### Signature

```zig
pub fn database(self: *@This()) Database
```

