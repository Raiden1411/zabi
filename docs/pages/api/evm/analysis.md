## AnalyzeBytecode
Analyzes the raw bytecode into a `analyzed` state. If the provided
code is already analyzed then it will just return it.

### Signature

```zig
pub fn analyzeBytecode(allocator: Allocator, code: Bytecode) Allocator.Error!Bytecode
```

## CreateJumpTable
Creates the jump table based on the provided bytecode. Assumes that
this was already padded in advance.

### Signature

```zig
pub fn createJumpTable(allocator: Allocator, prepared_code: []u8) Allocator.Error!JumpTable
```

