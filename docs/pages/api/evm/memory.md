## Memory

A extendable memory used by the evm interpreter.

### Properties

```zig
struct {
  /// The inner allocator used to grow the memory
  allocator: Allocator
  /// The underlaying memory buffer.
  buffer: []u8
  /// Set of memory checkpoints
  checkpoints: ArrayList(usize)
  /// The last memory checkpoint
  last_checkpoint: usize
  /// The max memory size
  memory_limit: u64
  /// The total allocated capacity of this memory.
  total_capacity: usize
}
```

## Error

Set of errors when resizing errors.

```zig
error{MaxMemoryReached}
```

### InitEmpty
Create the interpreter's memory. This will not error.
No initial capacity is set. It's essentially empty memory.

### Signature

```zig
pub fn initEmpty(allocator: Allocator, limit: ?u64) Memory
```

### InitWithDefaultCapacity
Creates the memory with default 4096 capacity.

### Signature

```zig
pub fn initWithDefaultCapacity(allocator: Allocator, limit: ?u64) Allocator.Error!Memory
```

### InitWithCapacity
Creates the memory with `capacity`.

### Signature

```zig
pub fn initWithCapacity(allocator: Allocator, capacity: usize, limit: ?u64) Allocator.Error!Memory
```

### FreeContext
Prepares the memory for returning to the previous context.

### Signature

```zig
pub fn freeContext(self: *Memory) void
```

### GetCurrentMemorySize
Gets the current size of the `Memory` range.

### Signature

```zig
pub fn getCurrentMemorySize(self: Memory) u64
```

### GetMemoryByte
Gets a byte from the list's buffer.

### Signature

```zig
pub fn getMemoryByte(self: Memory, offset: usize) u8
```

### GetMemoryWord
Gets a `Word` from memory of in other words it gets a slice
of 32 bytes from the inner memory buffer.

### Signature

```zig
pub fn getMemoryWord(self: Memory, offset: usize) Word
```

### GetSlice
Gets a memory slice based on the last checkpoints until the end of the buffer.

### Signature

```zig
pub fn getSlice(self: Memory) []u8
```

### MemoryCopy
Copies elements from one part of the buffer to another part of itself.
Asserts that the provided indexes are not out of bound.

### Signature

```zig
pub fn memoryCopy(self: *Memory, destination: usize, source: usize, length: usize) void
```

### NewContext
Prepares the memory for a new context.

### Signature

```zig
pub fn newContext(self: *Memory) Allocator.Error!void
```

### Resize
Resizes the underlaying memory buffer.
Uses the allocator's `resize` method in case it's possible.
If the new len is lower than the current buffer size data will be lost.

### Signature

```zig
pub fn resize(self: *Memory, new_len: usize) (Allocator.Error || Memory.Error)!void
```

### WordToInt
Converts a memory "Word" into a u256 number.
This reads the word as `Big` endian.

### Signature

```zig
pub fn wordToInt(self: Memory, offset: usize) u256
```

### WriteByte
Writes a single byte into this memory buffer.
This can overwrite to existing memory.

### Signature

```zig
pub fn writeByte(self: Memory, offset: usize, byte: u8) void
```

### WriteWord
Writes a memory `Word` into the memory buffer.
This can overwrite existing memory.

### Signature

```zig
pub fn writeWord(self: Memory, offset: usize, word: [32]u8) void
```

### WriteInt
Writes a `u256` number into the memory buffer.
This can overwrite to existing memory.

### Signature

```zig
pub fn writeInt(self: Memory, offset: usize, data: u256) void
```

### Write
Writes a slice to the memory buffer based on a offset.
This can overwrite to existing memory.

### Signature

```zig
pub fn write(self: Memory, offset: usize, data: []const u8) void
```

### WriteData
Writes a slice to a given offset in memory + the provided data's offset.
This can overwrite existing memory.

### Signature

```zig
pub fn writeData(self: Memory, offset: usize, data_offset: usize, len: usize, data: []u8) void
```

### Deinit
Frees the underlaying memory buffers.

### Signature

```zig
pub fn deinit(self: Memory) void
```

## Error

Set of errors when resizing errors.

```zig
error{MaxMemoryReached}
```

## AvailableWords
Returns number of words what would fit to provided number of bytes,
It rounds up the number bytes to number of words.

### Signature

```zig
pub inline fn availableWords(size: u64) usize
```

