## McopyInstruction
Runs the mcopy opcode for the interpreter.
0x5E -> MCOPY

### Signature

```zig
pub fn mcopyInstruction(self: *Interpreter) !void
```

## MloadInstruction
Runs the mload opcode for the interpreter.
0x51 -> MLOAD

### Signature

```zig
pub fn mloadInstruction(self: *Interpreter) !void
```

## MsizeInstruction
Runs the msize opcode for the interpreter.
0x59 -> MSIZE

### Signature

```zig
pub fn msizeInstruction(self: *Interpreter) !void
```

## MstoreInstruction
Runs the mstore opcode for the interpreter.
0x52 -> MSTORE

### Signature

```zig
pub fn mstoreInstruction(self: *Interpreter) !void
```

## Mstore8Instruction
Runs the mstore8 opcode for the interpreter.
0x53 -> MSTORE8

### Signature

```zig
pub fn mstore8Instruction(self: *Interpreter) !void
```

