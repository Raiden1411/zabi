# `serializeTransaction`

## Definition
Serializes a transaction. Supports signed & unsigned Berlin, London and Legacy Transactions

## Usage

The function takes in 2 arguments

- an allocator used to manage memory allocations
- The transaction you want to serialize.

```zig
const std = @import("std");
const serialize = @import("zabi").serialize;

const transaction_object = .{ ... };
const encoded = try serialize.serializeTransaction(std.testing.allocator, transaction_object);
```

### Returns

Type: `[]u8` -> **This is not hex encoded**
