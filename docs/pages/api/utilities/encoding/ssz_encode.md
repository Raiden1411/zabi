# `SSZ Encode`

## Definition

Encodes values into a Simple Serialize (SSZ) encoded value.

## Usage

It takes 2 argument.

- a allocator that is used to manage memory allocations.
- the value to be encoded. This can be almost any zig type.

```zig
const utils = @import(zabi).ssz;
const std = @import("std");

const data = .{
  .foo: u8 = 1,
  .bar: u32 = 3,
  .baz: bool = true,
};

try rlp.encodeSSZ(std.testing.allocator, data); // [!code focus:2]

// Result
// &[_]u8{ 0x01, 0x03, 0x00, 0x00, 0x00, 0x01 }
```

### Returns

Type: `[]u8` -> **This is not hex encoded**
