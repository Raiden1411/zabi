## CallInstruction
Performs call instruction for the interpreter.
CALL -> 0xF1

### Signature

```zig
pub fn callInstruction(self: *Interpreter) (error{FailedToLoadAccount} || Interpreter.InstructionErrors)!void
```

## CallCodeInstruction
Performs callcode instruction for the interpreter.
CALLCODE -> 0xF2

### Signature

```zig
pub fn callCodeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void
```

## CreateInstruction
Performs create instruction for the interpreter.
CREATE -> 0xF0 and CREATE2 -> 0xF5

### Signature

```zig
pub fn createInstruction(self: *Interpreter, is_create_2: bool) (error{ InstructionNotEnabled, Overflow } || Memory.Error || Interpreter.InstructionErrors)!void
```

## DelegateCallInstruction
Performs delegatecall instruction for the interpreter.
DELEGATECALL -> 0xF4

### Signature

```zig
pub fn delegateCallInstruction(self: *Interpreter) (error{InstructionNotEnabled} || Interpreter.InstructionErrors)!void
```

## StaticCallInstruction
Performs staticcall instruction for the interpreter.
STATICCALL -> 0xFA

### Signature

```zig
pub fn staticCallInstruction(self: *Interpreter) (error{InstructionNotEnabled} || Interpreter.InstructionErrors)!void
```

## CalculateCall
Calculates the gas cost for a `CALL` opcode.
Habides by EIP-150 where gas gets calculated as the min of available - (available / 64) or `local_gas_limit`

### Signature

```zig
pub inline fn calculateCall(self: *Interpreter, values_transfered: bool, is_cold: bool, new_account: bool, local_gas_limit: u64) ?u64
```

## GetMemoryInputsAndRanges
Gets the memory slice and the ranges used to grab it.
This also resizes the interpreter's memory.

### Signature

```zig
pub fn getMemoryInputsAndRanges(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { []u8, struct { u64, u64 } }
```

## ResizeMemoryAndGetRange
Resizes the memory as gets the offset ranges.

### Signature

```zig
pub fn resizeMemoryAndGetRange(self: *Interpreter, offset: u256, len: u256) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { u64, u64 }
```

