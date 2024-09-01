## DupInstruction
Runs the swap instructions opcodes for the interpreter.
0x80 .. 0x8F -> DUP1 .. DUP16

### Signature

```zig
pub fn dupInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void
```

## PopInstruction
Runs the pop opcode for the interpreter.
0x50 -> POP

### Signature

```zig
pub fn popInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## PushInstruction
Runs the push instructions opcodes for the interpreter.
0x60 .. 0x7F -> PUSH1 .. PUSH32

### Signature

```zig
pub fn pushInstruction(self: *Interpreter, size: u8) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void
```

## PushZeroInstruction
Runs the push0 opcode for the interpreter.
0x5F -> PUSH0

### Signature

```zig
pub fn pushZeroInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void
```

## SwapInstruction
Runs the swap instructions opcodes for the interpreter.
0x90 .. 0x9F -> SWAP1 .. SWAP16

### Signature

```zig
pub fn swapInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void
```

