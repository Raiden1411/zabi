## AndInstruction
Performs and instruction for the interpreter.
AND -> 0x15

### Signature

```zig
pub fn andInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ByteInstruction
Performs byte instruction for the interpreter.
AND -> 0x1A

### Signature

```zig
pub fn byteInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## EqualInstruction
Performs equal instruction for the interpreter.
EQ -> 0x14

### Signature

```zig
pub fn equalInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## GreaterThanInstruction
Performs equal instruction for the interpreter.
GT -> 0x11

### Signature

```zig
pub fn greaterThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## IsZeroInstruction
Performs iszero instruction for the interpreter.
ISZERO -> 0x15

### Signature

```zig
pub fn isZeroInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## LowerThanInstruction
Performs LT instruction for the interpreter.
LT -> 0x10

### Signature

```zig
pub fn lowerThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## NotInstruction
Performs NOT instruction for the interpreter.
NOT -> 0x19

### Signature

```zig
pub fn notInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## OrInstruction
Performs OR instruction for the interpreter.
OR -> 0x17

### Signature

```zig
pub fn orInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ShiftLeftInstruction
Performs shl instruction for the interpreter.
SHL -> 0x1B

### Signature

```zig
pub fn shiftLeftInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## ShiftRightInstruction
Performs shr instruction for the interpreter.
SHR -> 0x1C

### Signature

```zig
pub fn shiftRightInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignedGreaterThanInstruction
Performs SGT instruction for the interpreter.
SGT -> 0x12

### Signature

```zig
pub fn signedGreaterThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignedLowerThanInstruction
Performs SLT instruction for the interpreter.
SLT -> 0x12

### Signature

```zig
pub fn signedLowerThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## SignedShiftRightInstruction
Performs SAR instruction for the interpreter.
SAR -> 0x1D

### Signature

```zig
pub fn signedShiftRightInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## XorInstruction
Performs XOR instruction for the interpreter.
XOR -> 0x18

### Signature

```zig
pub fn xorInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

