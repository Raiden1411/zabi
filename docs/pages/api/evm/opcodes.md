## instruction_table

## Opcodes

EVM Opcodes.

## ToOpcode
Converts `u8` to associated opcode.\
Will return null for unknown opcodes

### Signature

```zig
pub fn toOpcode(num: u8) ?Opcodes
```

## InstructionTable

### Properties

```zig
inner: [256]Operations
```

### Init
Creates the instruction table.

### Signature

```zig
pub fn init() InstructionTable
```

### GetInstruction
Gets the associated operation for the provided opcode.

### Signature

```zig
pub fn getInstruction(self: @This(), opcode: u8) Operations
```

## Operations

Opcode operations and checks.

## MakeDupInstruction
Creates the dup instructions for the instruction table.

### Signature

```zig
pub fn makeDupInstruction(comptime dup_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Dup
### Signature

```zig
pub fn dup(self: *Interpreter) anyerror!void
```

## MakePushInstruction
Creates the push instructions for the instruction table.

### Signature

```zig
pub fn makePushInstruction(comptime push_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Push
### Signature

```zig
pub fn push(self: *Interpreter) anyerror!void
```

## MakeSwapInstruction
Creates the swap instructions for the instruction table.

### Signature

```zig
pub fn makeSwapInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Swap
### Signature

```zig
pub fn swap(self: *Interpreter) anyerror!void
```

## MakeLogInstruction
Creates the log instructions for the instruction table.

### Signature

```zig
pub fn makeLogInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) anyerror!void
```

## Log
### Signature

```zig
pub fn log(self: *Interpreter) anyerror!void
```

## MakeCreateInstruction
Creates the log instructions for the instruction table.

### Signature

```zig
pub fn makeCreateInstruction(comptime is_create2: bool) *const fn (ctx: *Interpreter) anyerror!void
```

## Log
### Signature

```zig
pub fn log(self: *Interpreter) anyerror!void
```

## MaxStack
Callculates the max avaliable size of the stack for the operation to execute.

### Signature

```zig
pub fn maxStack(comptime limit: comptime_int, comptime pop: comptime_int, comptime push: comptime_int) usize
```

