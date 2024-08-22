## Memory
A extendable memory used by the evm interpreter.

## InitEmpty
Create the interpreter's memory. This will not error.\
No initial capacity is set. It's essentially empty memory.

## InitWithDefaultCapacity
Creates the memory with default 4096 capacity.

## InitWithCapacity
Creates the memory with `capacity`.

## FreeContext
Prepares the memory for returning to the previous context.

## GetCurrentMemorySize
Gets the current size of the `Memory` range.

## GetMemoryByte
Gets a byte from the list's buffer.

## GetMemoryWord
Gets a `Word` from memory of in other words it gets a slice
of 32 bytes from the inner memory buffer.

## GetSlice
Gets a memory slice based on the last checkpoints until the end of the buffer.

## MemoryCopy
Copies elements from one part of the buffer to another part of itself.\
Asserts that the provided indexes are not out of bound.

## NewContext
Prepares the memory for a new context.

## Resize
Resizes the underlaying memory buffer.\
Uses the allocator's `resize` method in case it's possible.\
If the new len is lower than the current buffer size data will be lost.

## WordToInt
Converts a memory "Word" into a u256 number.\
This reads the word as `Big` endian.

## WriteByte
Writes a single byte into this memory buffer.\
This can overwrite to existing memory.

## WriteWord
Writes a memory `Word` into the memory buffer.\
This can overwrite existing memory.

## WriteInt
Writes a `u256` number into the memory buffer.\
This can overwrite to existing memory.

## Write
Writes a slice to the memory buffer based on a offset.\
This can overwrite to existing memory.

## WriteData
Writes a slice to a given offset in memory + the provided data's offset.\
This can overwrite existing memory.

## Deinit
Frees the underlaying memory buffers.

## AvailableWords

