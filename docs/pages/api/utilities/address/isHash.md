# `isHash`

## Definition

Checks if a given string is an hash

## Usage

It takes 1 argument.

- the string to check.

```zig
const not_address = "No";
const utils = @import(zabi).utils;
const std = @import("std");

utils.isHash(std.testing.allocator, not_address); // [!code focus:2]

// Result
// false
```

### Returns

Type: `bool`
