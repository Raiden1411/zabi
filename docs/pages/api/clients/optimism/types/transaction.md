## DepositTransaction

## DepositTransactionSigned

### Properties

```zig
hash: Hash
nonce: u64
blockHash: ?Hash
blockNumber: ?u64
transactionIndex: ?u64
from: Address
to: ?Address
value: Wei
gasPrice: Gwei
gas: Gwei
input: Hex
v: usize
/// Represented as values instead of the hash because
/// a valid signature is not guaranteed to be 32 bits
r: u256
/// Represented as values instead of the hash because
/// a valid signature is not guaranteed to be 32 bits
s: u256
type: TransactionTypes
sourceHash: Hex
mint: ?u256 = null
isSystemTx: ?bool = null
depositReceiptVersion: ?u64 = null
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## DepositData

## TransactionDeposited

## DepositTransactionEnvelope

