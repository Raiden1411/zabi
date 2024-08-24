## CallAction

Inputs for a call action.

### Properties

```zig
struct {
  /// The calldata of this action.
  inputs: []u8
  /// The return memory offset where the output of this call
  /// gets written to.
  return_memory_offset: struct { u64, u64 }
  /// The gas limit of this call.
  gas_limit: u64
  /// The account address of bytecode that is going to be executed.
  bytecode_address: Address
  /// Target address. This account's storage will get modified.
  target_address: Address
  /// The address that is invoking this call.
  caller: Address
  /// The call value. Depeding on the scheme value might not get transfered.
  value: CallValue
  /// The call scheme.
  scheme: CallScheme
  /// Whether this call is static or initialized inside a static call.
  is_static: bool
}
```

### Init
Creates an instance for this action.

### Signature

```zig
pub fn init(tx_env: TxEnviroment, gas_limit: u64) ?CallAction
```

## CallValue

Evm call value types.

### Properties

```zig
union(enum) {
  /// The concrete value that will get transfered from the caller to the callee.
  transfer: u256
  /// The transfer value that lives in limbo where the value gets set but
  /// it will **never** get transfered.
  limbo: u256
}
```

### GetCurrentValue
Gets the current value independent of the active union member.

### Signature

```zig
pub fn getCurrentValue(self: CallValue) u256
```

## CallScheme

EVM Call scheme.

### Properties

```zig
enum {
  call
  callcode
  delegate
  static
}
```

## CreateAction

Inputs for a create call.

### Properties

```zig
struct {
  /// Caller address of the EVM.
  caller: Address
  /// The schema used for the create action
  scheme: CreateScheme
  /// Value to transfer
  value: u256
  /// The contract's init code.
  init_code: []u8
  /// The gas limit of this call.
  gas_limit: u64
}
```

### Init
Creates an instance for this action.

### Signature

```zig
pub fn init(tx_env: TxEnviroment, gas_limit: u64) ?CallAction
```

## CreateScheme

EVM Create scheme.

## ReturnAction

The result of the interpreter operation

### Properties

```zig
struct {
  /// The result of the instruction execution.
  result: InterpreterStatus
  /// The return output slice.
  output: []u8
  /// The tracker with gas usage.
  gas: GasTracker
}
```

