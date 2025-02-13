## JournaledState

A journal of state changes internal to the EVM.

On each additional call, the depth of the journaled state is increased and a new journal is added.
The journal contains every state change that happens within that call, making it possible to revert changes made in a specific call.

### Properties

```zig
struct {
  /// The allocator used by the journal.
  allocator: Allocator
  /// The database used to grab information in case the journal doesn't have it.
  database: Database
  /// EIP-1153 transient storage
  transient_storage: AutoHashMapUnmanaged(struct { Address, u256 }, u256)
  /// The current journal state.
  state: AutoHashMapUnmanaged(Address, Account)
  /// List of emitted logs
  log_storage: ArrayListUnmanaged(Log)
  /// The current call stack depth.
  depth: usize
  /// The journal of state changes. One for each call.
  journal: ArrayListUnmanaged(ArrayListUnmanaged(JournalEntry))
  /// The spec id for the journal. Changes the behaviour depending on the current spec.
  spec: SpecId
  /// Warm loaded addresses are used to check if loaded address
  /// should be considered cold or warm loaded when the account
  /// is first accessed.
  warm_preloaded_address: AutoHashMapUnmanaged(Address, void)
}
```

## BasicErrors

Set of basic error when interacting with this journal.

```zig
Allocator.Error || error{UnexpectedError}
```

## RevertCheckpointError

Set of errors when performing revert actions.

```zig
Allocator.Error || error{ NonExistentAccount, InvalidStorageKey }
```

## LoadErrors

Set of errors when performing load or storage store.

```zig
RevertCheckpointError || error{UnexpectedError}
```

## TransferErrors

Set of errors when performing a value transfer.

```zig
BasicErrors || error{ NonExistentAccount, OutOfFunds, OverflowPayment }
```

## CreateAccountErrors

Set of possible basic database errors.

```zig
TransferErrors || LoadErrors || error{
        CreateCollision,
        BalanceOverflow,
    }
```

### Init
Sets up the initial state for this journal.

### Signature

```zig
pub fn init(
    self: *JournaledState,
    allocator: Allocator,
    spec_id: SpecId,
    db: Database,
) void
```

### Deinit
Clears any allocated memory.

### Signature

```zig
pub fn deinit(self: *JournaledState) void
```

### Checkpoint
Creates a new checkpoint and increase the call depth.

### Signature

```zig
pub fn checkpoint(self: *JournaledState) Allocator.Error!JournalCheckpoint
```

### CommitCheckpoint
Commits the checkpoint

### Signature

```zig
pub fn commitCheckpoint(self: *JournaledState) void
```

### CreateAccountCheckpoint
Creates an account with a checkpoint so that in case the account already exists
or the account is out of funds it's able to revert any journal entries.

A `account_created` entry is created along with a `balance_transfer` and `account_touched`.

### Signature

```zig
pub fn createAccountCheckpoint(
    self: *JournaledState,
    caller: Address,
    target_address: Address,
    balance: u256,
) CreateAccountErrors!JournalCheckpoint
```

### IncrementAccountNonce
Increments the nonce of an account.

A `nonce_changed` entry will be emitted.

### Signature

```zig
pub fn incrementAccountNonce(
    self: *JournaledState,
    address: Address,
) Allocator.Error!?u64
```

### LoadAccount
Loads an account from the state.

A `account_warmed` entry is added to the journal if the load was cold.

### Signature

```zig
pub fn loadAccount(
    self: *JournaledState,
    address: Address,
) BasicErrors!StateLoaded(Account)
```

### LoadCode
Loads the bytecode from an account

Returns empty bytecode if the code hash is equal to the Keccak256 hash of an empty string.
A `account_warmed` entry is added to the journal if the load was cold.

### Signature

```zig
pub fn loadCode(
    self: *JournaledState,
    address: Address,
) BasicErrors!StateLoaded(Account)
```

### Log
Appends the log to the log event list.

### Signature

```zig
pub fn log(self: *JournaledState, event: Log) Allocator.Error!void
```

### RevertCheckpoint
Reverts a checkpoint and uncommit's all of the journal entries.

### Signature

```zig
pub fn revertCheckpoint(
    self: *JournaledState,
    point: JournalCheckpoint,
) RevertCheckpointError!void
```

### RevertJournal
Reverts a list of journal entries. Depending on the type of entry different actions will be taken.

### Signature

```zig
pub fn revertJournal(
    self: *JournaledState,
    journal_entry: *ArrayListUnmanaged(JournalEntry),
) RevertCheckpointError!void
```

### SelfDestruct
Performs the self destruct action

Transfer the balance to the target address.

Balance will be lost if address and target are the same BUT when current spec enables Cancun,
this happens only when the account associated to address is created in the same transaction.

### Signature

```zig
pub fn selfDestruct(
    self: *JournaledState,
    address: Address,
    target: Address,
) LoadErrors!StateLoaded(SelfDestructResult)
```

### SetCode
Sets the bytecode for an account and generates the associated Keccak256 hash for that bytecode.

A `code_changed` entry will be emitted.

### Signature

```zig
pub fn setCode(
    self: *JournaledState,
    address: Address,
    code: Bytecode,
) (Allocator.Error || error{NonExistentAccount})!void
```

### SetCodeAndHash
Sets the bytecode and the Keccak256 hash for an associated account.

A `code_changed` entry will be emitted.

### Signature

```zig
pub fn setCodeAndHash(
    self: *JournaledState,
    address: Address,
    code: Bytecode,
    hash: Hash,
) (Allocator.Error || error{NonExistentAccount})!void
```

### Sload
Loads a value from the account storage based on the provided key.

Returns if the load was cold or not.

### Signature

```zig
pub fn sload(
    self: *JournaledState,
    address: Address,
    key: u256,
) LoadErrors!StateLoaded(u256)
```

### Sstore
Stores a value to the account's storage based on the provided index.

Returns if store was cold or not.

### Signature

```zig
pub fn sstore(
    self: *JournaledState,
    address: Address,
    key: u256,
    new: u256,
) LoadErrors!StateLoaded(SStoreResult)
```

### Tload
Read transient storage tied to the account.

EIP-1153: Transient storage opcodes

### Signature

```zig
pub fn tload(
    self: *JournaledState,
    address: Address,
    key: u256,
) u256
```

### TouchAccount
Sets an account as touched.

### Signature

```zig
pub fn touchAccount(
    self: *JournaledState,
    address: Address,
) Allocator.Error!void
```

### Transfer
Transfers the value from one account to other another account.

A `balance_transfer` entry is created.

### Signature

```zig
pub fn transfer(
    self: *JournaledState,
    from: Address,
    to: Address,
    value: u256,
) TransferErrors!void
```

### Tstore
Store transient storage tied to the account.

If values is different add entry to the journal
so that old state can be reverted if that action is needed.

EIP-1153: Transient storage opcodes

### Signature

```zig
pub fn tstore(
    self: *JournaledState,
    address: Address,
    key: u256,
    value: u256,
) Allocator.Error!void
```

### UpdateSpecId
Updates the spec id for this journal.

### Signature

```zig
pub fn updateSpecId(
    self: *JournaledState,
    spec_id: SpecId,
) void
```

## BasicErrors

Set of basic error when interacting with this journal.

```zig
Allocator.Error || error{UnexpectedError}
```

## RevertCheckpointError

Set of errors when performing revert actions.

```zig
Allocator.Error || error{ NonExistentAccount, InvalidStorageKey }
```

## LoadErrors

Set of errors when performing load or storage store.

```zig
RevertCheckpointError || error{UnexpectedError}
```

## TransferErrors

Set of errors when performing a value transfer.

```zig
BasicErrors || error{ NonExistentAccount, OutOfFunds, OverflowPayment }
```

## CreateAccountErrors

Set of possible basic database errors.

```zig
TransferErrors || LoadErrors || error{
        CreateCollision,
        BalanceOverflow,
    }
```

## JournalCheckpoint

Journaling checkpoint in case the journal needs to revert.

### Properties

```zig
struct {
  journal_checkpoint: usize
  logs_checkpoint: usize
}
```

## JournalEntry

Representation of an journal entry.

### Properties

```zig
union(enum) {
  /// Entry used to mark an account that is warm inside EVM in regards to EIP-2929 AccessList.
  account_warmed: struct {
        address: Address,
    }
  /// Entry for marking an account to be destroyed and journal balance to be reverted
  account_destroyed: struct {
        address: Address,
        target: Address,
        was_destroyed: bool,
        had_balance: u256,
    }
  /// Loading account does not mean that account will need to be added to MerkleTree (touched).
  /// Only when account is called (to execute contract or transfer balance) only then account is made touched.
  account_touched: struct {
        address: Address,
    }
  /// Entry for transfering balance between two accounts
  balance_transfer: struct {
        from: Address,
        to: Address,
        balance: u256,
    }
  /// Entry for increment the nonce of an account
  nonce_changed: struct {
        address: Address,
    }
  /// Entry for creating an account
  account_created: struct {
        address: Address,
    }
  /// Entry used to track storage changes
  storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    }
  /// Entry used to track storage warming introduced by EIP-2929.
  storage_warmed: struct {
        address: Address,
        key: u256,
    }
  /// Entry used to track an EIP-1153 transient storage change.
  transient_storage_changed: struct {
        address: Address,
        key: u256,
        had_value: u256,
    }
  /// Entry used to change the bytecode associated with an account.
  code_changed: struct {
        address: Address,
    }
}
```

## StateLoaded
Data structure returned when performing loads.

### Signature

```zig
pub fn StateLoaded(comptime T: type) type
```

