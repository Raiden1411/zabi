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

## ParseTransaction
Parses unsigned serialized transactions. Creates and arena to manage memory.
Caller needs to call deinit to free memory.

### Signature

```zig
pub fn parseTransaction(allocator: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelope)
```

## ParseTransactionLeaky
Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseTransactionLeaky(allocator: Allocator, serialized: []const u8) !TransactionEnvelope
```

## ParseEip4844Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip4844Transaction(allocator: Allocator, serialized: []const u8) !CancunTransactionEnvelope
```

## ParseEip1559Transaction
Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip1559Transaction(allocator: Allocator, serialized: []const u8) !LondonTransactionEnvelope
```

## ParseEip2930Transaction
Parses unsigned serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseEip2930Transaction(allocator: Allocator, serialized: []const u8) !BerlinTransactionEnvelope
```

## ParseLegacyTransaction
Parses unsigned serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseLegacyTransaction(allocator: Allocator, serialized: []const u8) !LegacyTransactionEnvelope
```

## ParseSignedTransaction
Parses signed serialized transactions. Creates and arena to manage memory.
Caller needs to call deinit to free memory.

### Signature

```zig
pub fn parseSignedTransaction(allocator: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelopeSigned)
```

## ParseSignedTransactionLeaky
Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedTransactionLeaky(allocator: Allocator, serialized: []const u8) !TransactionEnvelopeSigned
```

## ParseSignedEip4844Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip4844Transaction(allocator: Allocator, serialized: []const u8) !CancunTransactionEnvelopeSigned
```

## ParseSignedEip1559Transaction
Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip1559Transaction(allocator: Allocator, serialized: []const u8) !LondonTransactionEnvelopeSigned
```

## ParseSignedEip2930Transaction
Parses signed serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedEip2930Transaction(allocator: Allocator, serialized: []const u8) !BerlinTransactionEnvelopeSigned
```

## ParseSignedLegacyTransaction
Parses signed serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseSignedLegacyTransaction(allocator: Allocator, serialized: []const u8) !LegacyTransactionEnvelopeSigned
```

## ParseAccessList
Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.

### Signature

```zig
pub fn parseAccessList(allocator: Allocator, access_list: []const StructToTupleType(AccessList)) ![]const AccessList
```

