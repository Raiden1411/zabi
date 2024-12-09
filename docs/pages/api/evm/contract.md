## Contract

EVM contract representation.

### Properties

```zig
struct {
  /// The bytecode associated with this contract.
  bytecode: Bytecode
  /// Address that called this contract.
  caller: Address
  /// Keccak hash of the bytecode.
  code_hash: ?Hash = null
  /// The calldata input to use in this contract.
  input: []u8
  /// The address of this contract.
  target_address: Address
  /// Value in wei associated with this contract.
  value: u256
}
```

### Init
Creates a contract instance from the provided inputs.
This will also prepare the provided bytecode in case it's given in a `raw` state.

### Signature

```zig
pub fn init(
    allocator: Allocator,
    data: []u8,
    bytecode: Bytecode,
    hash: ?Hash,
    value: u256,
    caller: Address,
    target_address: Address,
) Allocator.Error!Contract
```

### InitFromEnviroment
Creates a contract instance from a given enviroment.
This will also prepare the provided bytecode in case it's given in a `raw` state.

### Signature

```zig
pub fn initFromEnviroment(allocator: Allocator, env: EVMEnviroment, bytecode: Bytecode, hash: ?Hash) !Contract
```

### Deinit
Clears the bytecode in case it's analyzed.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

### IsValidJump
Returns if the provided target result in a valid jump dest.

### Signature

```zig
pub fn isValidJump(self: Contract, target: usize) bool
```

