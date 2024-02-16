# `isAddress`

## Definition

Checks if a given string is an ethereum address.

## Usage

It takes 1 argument.

- the string to check.

```zig
const not_address = "No";
const utils = @import(zabi).utils;
const std = @import("std");

// This will allocate because it will checksum to make sure // [!code focus:2]
// that the address is valid. // [!code focus:2]
try utils.isAddress(std.testing.allocator, not_address); // [!code focus:2]

// Result
// false
```

### Returns

Type: `bool`
