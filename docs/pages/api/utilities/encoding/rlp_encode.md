# `RLP Encode`

## Definition

Encodes values into a Recursive-Length Prefix (RLP) encoded value.
`C` pointers are not supported.

## Usage

It takes 2 argument.

- an allocator that is used to manage memory allocations.
- the values to be encoded. This is expected to be a tuple of possible values

```zig
const utils = @import(zabi).rlp;
const std = @import("std");

try rlp.encode(std.testing.allocator, .{"dog"}); // [!code focus:2]

// Result
// &[_]u8{ 0x83, 0x64, 0x6f, 0x67 }
```

### Returns

Type: `[]u8` -> **This is not hex encoded**
