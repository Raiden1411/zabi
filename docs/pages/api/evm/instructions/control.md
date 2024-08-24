## ConditionalJumpInstruction
Runs the jumpi instruction opcode for the interpreter.\
0x57 -> JUMPI

### Signature

```zig
pub fn conditionalJumpInstruction(self: *Interpreter) !void
```

## ProgramCounterInstruction
Runs the pc instruction opcode for the interpreter.\
0x58 -> PC

### Signature

```zig
pub fn programCounterInstruction(self: *Interpreter) !void
```

## JumpInstruction
Runs the jump instruction opcode for the interpreter.\
0x56 -> JUMP

### Signature

```zig
pub fn jumpInstruction(self: *Interpreter) !void
```

## JumpDestInstruction
Runs the jumpdest instruction opcode for the interpreter.\
0x5B -> JUMPDEST

### Signature

```zig
pub fn jumpDestInstruction(self: *Interpreter) !void
```

## InvalidInstruction
Runs the invalid instruction opcode for the interpreter.\
0xFE -> INVALID

### Signature

```zig
pub fn invalidInstruction(self: *Interpreter) !void
```

## StopInstruction
Runs the stop instruction opcode for the interpreter.\
0x00 -> STOP

### Signature

```zig
pub fn stopInstruction(self: *Interpreter) !void
```

## ReturnInstruction
Runs the return instruction opcode for the interpreter.\
0xF3 -> RETURN

### Signature

```zig
pub fn returnInstruction(self: *Interpreter) !void
```

## RevertInstruction
Runs the rever instruction opcode for the interpreter.\
0xFD -> REVERT

### Signature

```zig
pub fn revertInstruction(self: *Interpreter) !void
```

## UnknownInstruction
Instructions that gets ran if there is no associated opcode.

### Signature

```zig
pub fn unknownInstruction(self: *Interpreter) !void
```

