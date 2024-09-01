## HostInstructionErrors

Set of possible errors for host instructions.

```zig
Interpreter.InstructionErrors || error{UnexpectedError}
```

## BalanceInstruction
Runs the balance opcode for the interpreter.
0x31 -> BALANCE

### Signature

```zig
pub fn balanceInstruction(self: *Interpreter) HostInstructionErrors!void
```

## BlockHashInstruction
Runs the blockhash opcode for the interpreter.
0x40 -> BLOCKHASH

### Signature

```zig
pub fn blockHashInstruction(self: *Interpreter) HostInstructionErrors!void
```

## ExtCodeCopyInstruction
Runs the extcodecopy opcode for the interpreter.
0x3B -> EXTCODECOPY

### Signature

```zig
pub fn extCodeCopyInstruction(self: *Interpreter) (HostInstructionErrors || Memory.Error || error{Overflow})!void
```

## ExtCodeHashInstruction
Runs the extcodehash opcode for the interpreter.
0x3F -> EXTCODEHASH

### Signature

```zig
pub fn extCodeHashInstruction(self: *Interpreter) HostInstructionErrors!void
```

## ExtCodeSizeInstruction
Runs the extcodesize opcode for the interpreter.
0x3B -> EXTCODESIZE

### Signature

```zig
pub fn extCodeSizeInstruction(self: *Interpreter) HostInstructionErrors!void
```

## LogInstruction
Runs the logs opcode for the interpreter.
0xA0..0xA4 -> LOG0..LOG4

### Signature

```zig
pub fn logInstruction(self: *Interpreter, size: u8) (HostInstructionErrors || Memory.Error || error{Overflow})!void
```

## SelfBalanceInstruction
Runs the selfbalance opcode for the interpreter.
0x47 -> SELFBALANCE

### Signature

```zig
pub fn selfBalanceInstruction(self: *Interpreter) (HostInstructionErrors || error{InstructionNotEnabled})!void
```

## SelfDestructInstruction
Runs the selfbalance opcode for the interpreter.
0xFF -> SELFDESTRUCT

### Signature

```zig
pub fn selfDestructInstruction(self: *Interpreter) HostInstructionErrors!void
```

## SloadInstruction
Runs the sload opcode for the interpreter.
0x54 -> SLOAD

### Signature

```zig
pub fn sloadInstruction(self: *Interpreter) HostInstructionErrors!void
```

## SstoreInstruction
Runs the sstore opcode for the interpreter.
0x55 -> SSTORE

### Signature

```zig
pub fn sstoreInstruction(self: *Interpreter) HostInstructionErrors!void
```

## TloadInstruction
Runs the tload opcode for the interpreter.
0x5C -> TLOAD

### Signature

```zig
pub fn tloadInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void
```

## TstoreInstruction
Runs the tstore opcode for the interpreter.
0x5D -> TSTORE

### Signature

```zig
pub fn tstoreInstruction(self: *Interpreter) (HostInstructionErrors || error{InstructionNotEnabled})!void
```

