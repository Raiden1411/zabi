# `RLP Decode`

## Definition

Encodes values into a Recursive-Length Prefix (RLP) encoded value.
`C` and `Many` pointers, `Unions` are not supported.

## Usage

It takes 3 argument.

- an allocator that is used to manage memory allocations.
- the expected return type that will be used to reflect upon it.
- the values to be encoded. This is expected to be a tuple of possible values

```zig
const utils = @import(zabi).rlp;
const std = @import("std");

try rlp.decode(std.testing.allocator, []const u8, &[_]u8{0x83, 0x64, 0x6f, 0x67}); // [!code focus:2]

// Result
// "dog"
```

### Returns

Type: `!T` -> The type that is set when calling this function plus the error union.
