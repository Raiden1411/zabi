## ParsedTransaction
### Signature

```zig
pub fn ParsedTransaction(comptime T: type) type
```

## Deinit
### Signature

```zig
pub fn deinit(self: @This()) void
```

## ParseTransactionErrors

```zig
RlpDecodeErrors || error{ InvalidRecoveryId, InvalidTransactionType, NoSpaceLeft, InvalidLength }
```

## ParseTransaction
Parses unsigned serialized transactions. Creates and arena to manage memory.\
This is for the cases where we need to decode access list or if the serialized transaction contains data.

**Example**
```zig
const tx: LondonTransactionEnvelope = .{
    .chainId = 1,
    .nonce = 0,
    .maxPriorityFeePerGas = 0,
    .maxFeePerGas = 0,
    .gas = 0,
    .to = null,
    .value = 0,
    .data = null,
    .accessList = &.{},
};
const min = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
defer testing.allocator.free(min);

const parsed = try parseTransaction(testing.allocator, min);
defer parsed.deinit();
```

### Signature

```zig
pub fn parseTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!ParsedTransaction(TransactionEnvelope)
```

## ParseTransactionLeaky
Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

This is usefull for cases where the transaction object is expected to not have any allocated memory and it faster to decode because of it.

**Example**
```zig
const tx: LondonTransactionEnvelope = .{
    .chainId = 1,
    .nonce = 0,
    .maxPriorityFeePerGas = 0,
    .maxFeePerGas = 0,
    .gas = 0,
    .to = null,
    .value = 0,
    .data = null,
    .accessList = &.{},
};
const min = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
defer testing.allocator.free(min);

const parsed = try parseTransactionLeaky(testing.allocator, min);
```

### Signature

```zig
pub fn parseTransactionLeaky(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!TransactionEnvelope
```

## ParseEip4844Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip4844Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!CancunTransactionEnvelope
```

## ParseEip1559Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip1559Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LondonTransactionEnvelope
```

## ParseEip2930Transaction
Parses unsigned serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip2930Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!BerlinTransactionEnvelope
```

## ParseLegacyTransaction
Parses unsigned serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseLegacyTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LegacyTransactionEnvelope
```

## ParseSignedTransaction
Parses signed serialized transactions. Creates and arena to manage memory.
Caller needs to call deinit to free memory.

### Signature

```zig
pub fn parseSignedTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!ParsedTransaction(TransactionEnvelopeSigned)
```

## ParseSignedTransactionLeaky
Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedTransactionLeaky(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!TransactionEnvelopeSigned
```

## ParseSignedEip4844Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip4844Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!CancunTransactionEnvelopeSigned
```

## ParseSignedEip1559Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip1559Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LondonTransactionEnvelopeSigned
```

## ParseSignedEip2930Transaction
Parses signed serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip2930Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!BerlinTransactionEnvelopeSigned
```

## ParseSignedLegacyTransaction
Parses signed serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedLegacyTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LegacyTransactionEnvelopeSigned
```

## ParseAccessList
Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseAccessList(allocator: Allocator, access_list: []const StructToTupleType(AccessList)) Allocator.Error![]const AccessList
```

