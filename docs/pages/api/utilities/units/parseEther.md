# `parseEther`

## Definition

Converts a number to the representation in wei

## Usage

It takes 1 argument.

- the number to convert.

```zig
const utils = @import(zabi).utils;
const std = @import("std");

utils.parseEther(1); // [!code focus:2]

// Result
// 1000000000000000000
```

### Returns

Type: `u256`
