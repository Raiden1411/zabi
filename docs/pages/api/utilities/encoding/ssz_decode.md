# `SSZ Decode`

## Definition

Decodes values from a Simple Serialize (SSZ) encoded value to a native zig type.

## Usage

It takes 2 argument.

- The type that you want to decode to.
- the encoded value to be decoded.

```zig
const utils = @import(zabi).ssz;
const std = @import("std");

const Data = struct {
  foo: u8,
  bar: u32,
  baz: bool,
};

const encoded = &[_]u8{ 0x01, 0x03, 0x00, 0x00, 0x00, 0x01 };
try rlp.decodeSSZ(Data, encoded); // [!code focus:2]

// Result
//.{
//  .foo: u8 = 1,
//  .bar: u32 = 3,
//  .baz: bool = true,
// };
```

### Returns

Type: `T` -> The assigned type that was decode against
