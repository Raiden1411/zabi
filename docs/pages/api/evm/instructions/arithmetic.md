## AddInstruction
Performs add instruction for the interpreter.
ADD -> 0x01

### Signature

```zig
pub fn addInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## DivInstruction
Performs div instruction for the interpreter.
DIV -> 0x04

### Signature

```zig
pub fn divInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ExponentInstruction
Performs exponent instruction for the interpreter.
EXP -> 0x0A

### Signature

```zig
pub fn exponentInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{Overflow})!void
```

## ModAdditionInstruction
Performs addition + mod instruction for the interpreter.
ADDMOD -> 0x08

### Signature

```zig
pub fn modAdditionInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ModInstruction
Performs mod instruction for the interpreter.
MOD -> 0x06

### Signature

```zig
pub fn modInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ModMultiplicationInstruction
Performs mul + mod instruction for the interpreter.
MULMOD -> 0x09

### Signature

```zig
pub fn modMultiplicationInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## MulInstruction
Performs mul instruction for the interpreter.
MUL -> 0x02

### Signature

```zig
pub fn mulInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignedDivInstruction
Performs signed division instruction for the interpreter.
SDIV -> 0x05

### Signature

```zig
pub fn signedDivInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignExtendInstruction
Performs signextend instruction for the interpreter.
SIGNEXTEND -> 0x0B

### Signature

```zig
pub fn signExtendInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignedModInstruction
Performs sub instruction for the interpreter.
SMOD -> 0x07

### Signature

```zig
pub fn signedModInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SubInstruction
Performs sub instruction for the interpreter.
SUB -> 0x03

### Signature

```zig
pub fn subInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

