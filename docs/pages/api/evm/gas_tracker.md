## QUICK_STEP

## FASTEST_STEP

## FAST_STEP

## MID_STEP

## SLOW_STEP

## EXT_STEP

## JUMPDEST

## SELFDESTRUCT

## CREATE

## CALLVALUE

## NEWACCOUNT

## LOG

## LOGDATA

## LOGTOPIC

## KECCAK256

## KECCAK256WORD

## BLOCKHASH

## CODEDEPOSIT

## CONDITION_JUMP_GAS

## RETF_GAS

## DATA_LOAD_GAS

## ISTANBUL_SLOAD_GAS

EIP-1884: Repricing for trie-size-dependent opcodes

## SSTORE_SET

## SSTORE_RESET

## REFUND_SSTORE_CLEARS

## TRANSACTION_ZERO_DATA

## TRANSACTION_NON_ZERO_DATA_INIT

## TRANSACTION_NON_ZERO_DATA_FRONTIER

## EOF_CREATE_GAS

## ACCESS_LIST_ADDRESS

## ACCESS_LIST_STORAGE_KEY

## COLD_SLOAD_COST

## COLD_ACCOUNT_ACCESS_COST

## WARM_STORAGE_READ_COST

## WARM_SSTORE_RESET

## INITCODE_WORD_COST

EIP-3860 : Limit and meter initcode

## CALL_STIPEND

## GasTracker

Gas tracker used to track gas usage by the EVM.

### Properties

```zig
struct {
  /// The gas size limit that the interpreter can run.
  gas_limit: u64
  /// The amount of gas that has already been used.
  used_amount: u64
  /// The amount of gas to refund to the caller.
  refund_amount: i64
}
```

### Init
Sets the tracker's initial state.

### Signature

```zig
pub fn init(gas_limit: u64) GasTracker
```

### AvailableGas
Returns the remaining gas that can be used.

### Signature

```zig
pub fn availableGas(self: GasTracker) u64
```

### UpdateTracker
Updates the gas tracker based on the opcode cost.

### Signature

```zig
pub inline fn updateTracker(self: *GasTracker, cost: u64) error{ OutOfGas, GasOverflow }!void
```

## CalculateCallCost
Calculates the gas cost for the `CALL` opcode.

### Signature

```zig
pub inline fn calculateCallCost(spec: SpecId, values_transfered: bool, is_cold: bool, new_account: bool) u64
```

## CalculateCodeSizeCost
Calculates the gas cost for the `EXTCODESIZE` opcode.

### Signature

```zig
pub inline fn calculateCodeSizeCost(spec: SpecId, is_cold: bool) u64
```

## CalculateCostPerMemoryWord
Calculates the gas cost per `Memory` word.\
Returns null in case of overflow.

### Signature

```zig
pub inline fn calculateCostPerMemoryWord(length: u64, multiple: u64) ?u64
```

## CalculateCreateCost
Calculates the cost of using the `CREATE` opcode.\
**PANICS** if the gas cost overflows

### Signature

```zig
pub inline fn calculateCreateCost(length: u64) u64
```

## CalculateCreate2Cost
Calculates the cost of using the `CREATE2` opcode.\
Returns null in case of overflow.

### Signature

```zig
pub inline fn calculateCreate2Cost(length: u64) ?u64
```

## CalculateExponentCost
Calculates the gas used for the `EXP` opcode.

### Signature

```zig
pub inline fn calculateExponentCost(exp: u256, spec: SpecId) !u64
```

## CalculateExtCodeCopyCost
Calculates the gas used for the `EXTCODECOPY` opcode.

### Signature

```zig
pub inline fn calculateExtCodeCopyCost(spec: SpecId, len: u64, is_cold: bool) ?u64
```

## CalculateKeccakCost
Calculates the cost of using the `KECCAK256` opcode.\
Returns null in case of overflow.

### Signature

```zig
pub inline fn calculateKeccakCost(length: u64) ?u64
```

## CalculateLogCost
Calculates the gas cost for a LOG instruction.

### Signature

```zig
pub inline fn calculateLogCost(size: u8, length: u64) ?u64
```

## CalculateMemoryCost
Calculates the memory expansion cost based on the provided `word_count`

### Signature

```zig
pub inline fn calculateMemoryCost(count: u64) u64
```

## CalculateMemoryCopyLowCost
Calculates the cost of a memory copy.

### Signature

```zig
pub inline fn calculateMemoryCopyLowCost(length: u64) ?u64
```

## CalculateFrontierSstoreCost
Calculates the cost of the `SSTORE` opcode after the `FRONTIER` spec.

### Signature

```zig
pub inline fn calculateFrontierSstoreCost(current: u256, new: u256) u64
```

## CalculateIstanbulSstoreCost
Calculates the cost of the `SSTORE` opcode after the `ISTANBUL` spec.

### Signature

```zig
pub inline fn calculateIstanbulSstoreCost(original: u256, current: u256, new: u256) u64
```

## CalculateSloadCost
Calculate the cost of an `SLOAD` opcode based on the spec and if the access is cold
or warm if the `BERLIN` spec is enabled.

### Signature

```zig
pub inline fn calculateSloadCost(spec: SpecId, is_cold: bool) u64
```

## CalculateSstoreCost
Calculate the cost of an `SSTORE` opcode based on the spec, if the access is cold
and the value in storage. Returns null if the spec is `ISTANBUL` enabled and the provided
gas is lower than `CALL_STIPEND`.

### Signature

```zig
pub inline fn calculateSstoreCost(spec: SpecId, original: u256, current: u256, new: u256, gas: u64, is_cold: bool) ?u64
```

## CalculateSstoreRefund
Calculate the refund of an `SSTORE` opcode.

### Signature

```zig
pub inline fn calculateSstoreRefund(spec: SpecId, original: u256, current: u256, new: u256) i64
```

## CalculateSelfDestructCost
Calculate the cost of an `SELFDESTRUCT` opcode based on the spec and it's result.

### Signature

```zig
pub inline fn calculateSelfDestructCost(spec: SpecId, result: SelfDestructResult) u64
```

## WarmOrColdCost
Returns the gas cost for reading from a `warm` or `cold` storage slot.

### Signature

```zig
pub inline fn warmOrColdCost(cold: bool) u64
```

