## Bytecode

State of the contract's bytecode.

### Properties

```zig
raw: []u8
analyzed: AnalyzedBytecode
```

### Deinit
Clears the analyzed jump table.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

### GetJumpTable
Returns the jump_table is the bytecode state is `analyzed`
otherwise it will return null.

### Signature

```zig
pub fn getJumpTable(self: @This()) ?JumpTable
```

### GetCodeBytes
Grabs the bytecode independent of the current state.

### Signature

```zig
pub fn getCodeBytes(self: @This()) []u8
```

## AnalyzedBytecode

Representation of the analyzed bytecode.

### Properties

```zig
bytecode: []u8
original_length: usize
jump_table: JumpTable
```

### Init
Creates an instance of `AnalyzedBytecode`.

### Signature

```zig
pub fn init(allocator: Allocator, raw: []u8) Allocator.Error!AnalyzedBytecode
```

### Deinit
Free's the underlaying allocated memory
Assumes that the bytecode was already padded and memory was allocated.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

## JumpTable

Essentially a `BitVec`

### Properties

```zig
bytes: []u8
```

### Init
Creates the jump table. Provided size must follow the two's complement.

### Signature

```zig
pub fn init(allocator: Allocator, value: bool, size: usize) Allocator.Error!JumpTable
```

### Deinit
Free's the underlaying buffer.

### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

### Set
Sets or unset a bit at the given position.

### Signature

```zig
pub fn set(self: @This(), position: usize, value: bool) void
```

### Peek
Gets if a bit is set at a given position.

### Signature

```zig
pub fn peek(self: @This(), position: usize) u1
```

### IsValid
Check if the provided position results in a valid bit set.

### Signature

```zig
pub fn isValid(self: @This(), position: usize) bool
```

