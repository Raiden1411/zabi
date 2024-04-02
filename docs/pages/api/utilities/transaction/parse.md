# `parseTransaction`

## Definition
Parses a serialized RLP-encoded transaction. Supports signed & unsigned Berlin, London and Legacy Transactions

## Usage

The function takes in 2 arguments

- an allocator used to manage memory allocations
- The hex encoded serialized transaction.

All allocation will be managed by a `ArenaAllocator`. You must call `deinit()` to free the memory.

```zig
const std = @import("std");
const parse = @import("zabi").parse_transaction;

const encoded = "02c90180808080808080c0"

const decoded = try parse.parseTransaction(std.testing.allocator, encoded);
defer decoded.deinit();
```

If you wanted to parse transactions that were signed consider using `parseTransactionSigned`

```zig
const std = @import("std");
const parse = @import("zabi").parse_transaction;

const encoded = "02f874827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a0d4d68c02302962fa53289fda5616c9e19a9d63b3956d63d177097143b2093e3ea025e1dd76721b4fc48eb5e2f91bf9132699036deccd45b3fa9d77b1d9b7628fb2"

const decoded = try parse.parseTransactionSigned(std.testing.allocator, encoded);
defer decoded.deinit();
```

### Returns

Type: `ParsedTransaction`

## ParsedTransaction

```zig
fn ParsedTransaction(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void { ... }
    };
}
```
