# `toChecksum`

## Definition

Checksums an ethereum address.

## Usage

It takes 1 argument.

- the address to checksum.

```zig
const address = "0x407d73d8a49eeb85d32cf465507dd71d507100c1";
const utils = @import(zabi).utils;
const std = @import("std");

const result = try utils.toChecksum(std.testing.allocator, address); // [!code focus:2]

// Result
// 0x407D73d8a49eeb85D32Cf465507dd71d507100c1
```

### Returns

Type: `[]u8` -> The hex encoded address.
