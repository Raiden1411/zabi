## AddressInstruction
Runs the address instructions opcodes for the interpreter.\
0x30 -> ADDRESS

### Signature

```zig
pub fn addressInstruction(self: *Interpreter) !void
```

## CallerInstruction
Runs the caller instructions opcodes for the interpreter.\
0x33 -> CALLER

### Signature

```zig
pub fn callerInstruction(self: *Interpreter) !void
```

## CallDataCopyInstruction
Runs the calldatacopy instructions opcodes for the interpreter.\
0x35 -> CALLDATACOPY

### Signature

```zig
pub fn callDataCopyInstruction(self: *Interpreter) !void
```

## CallDataLoadInstruction
Runs the calldataload instructions opcodes for the interpreter.\
0x37 -> CALLDATALOAD

### Signature

```zig
pub fn callDataLoadInstruction(self: *Interpreter) !void
```

## CallDataSizeInstruction
Runs the calldatasize instructions opcodes for the interpreter.\
0x36 -> CALLDATASIZE

### Signature

```zig
pub fn callDataSizeInstruction(self: *Interpreter) !void
```

## CallValueInstruction
Runs the calldatasize instructions opcodes for the interpreter.\
0x34 -> CALLVALUE

### Signature

```zig
pub fn callValueInstruction(self: *Interpreter) !void
```

## CodeCopyInstruction
Runs the codecopy instructions opcodes for the interpreter.\
0x39 -> CODECOPY

### Signature

```zig
pub fn codeCopyInstruction(self: *Interpreter) !void
```

## CodeSizeInstruction
Runs the codesize instructions opcodes for the interpreter.\
0x38 -> CODESIZE

### Signature

```zig
pub fn codeSizeInstruction(self: *Interpreter) !void
```

## GasInstruction
Runs the gas instructions opcodes for the interpreter.\
0x3A -> GAS

### Signature

```zig
pub fn gasInstruction(self: *Interpreter) !void
```

## KeccakInstruction
Runs the keccak instructions opcodes for the interpreter.\
0x20 -> KECCAK

### Signature

```zig
pub fn keccakInstruction(self: *Interpreter) !void
```

## ReturnDataSizeInstruction
Runs the returndatasize instructions opcodes for the interpreter.\
0x3D -> RETURNDATACOPY

### Signature

```zig
pub fn returnDataSizeInstruction(self: *Interpreter) !void
```

## ReturnDataCopyInstruction
Runs the returndatasize instructions opcodes for the interpreter.\
0x3E -> RETURNDATASIZE

### Signature

```zig
pub fn returnDataCopyInstruction(self: *Interpreter) !void
```

