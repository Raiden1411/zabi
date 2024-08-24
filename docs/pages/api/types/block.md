## BlockTag

Block tag used for RPC requests.

```zig
enum { latest, earliest, pending, safe, finalized }
```

## BalanceBlockTag

Specific tags used in some RPC requests

## ProofBlockTag

Specific tags used in some RPC requests

## BlockRequest

Used in the RPC method requests

### Properties

```zig
block_number: ?u64 = null
tag: ?BlockTag = .latest
include_transaction_objects: ?bool = false
```

## BlockHashRequest

Used in the RPC method requests

## BalanceRequest

Used in the RPC method requests

### Properties

```zig
address: Address
block_number: ?u64 = null
tag: ?BalanceBlockTag = .latest
```

## BlockNumberRequest

Used in the RPC method requests

## Withdrawal

Withdrawal field struct type.

### Properties

```zig
index: u64
validatorIndex: u64
address: Address
amount: Wei
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

## LegacyBlock

The most common block that can be found before the
ethereum merge. Doesn't contain the `withdrawals` or
`withdrawalsRoot` fields.

### Properties

```zig
baseFeePerGas: ?Gwei = null
difficulty: u256
extraData: Hex
gasLimit: Gwei
gasUsed: Gwei
hash: ?Hash
logsBloom: ?Hex
miner: Address
mixHash: ?Hash = null
nonce: ?u64
number: ?u64
parentHash: Hash
receiptsRoot: Hash
sealFields: ?[]const Hex = null
sha3Uncles: Hash
size: u64
stateRoot: Hash
timestamp: u64
totalDifficulty: ?u256 = null
transactions: ?BlockTransactions = null
transactionsRoot: Hash
uncles: ?[]const Hash = null
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

## ArbitrumBlock

The most common block that can be found before the
ethereum merge. Doesn't contain the `withdrawals` or
`withdrawalsRoot` fields.

### Properties

```zig
baseFeePerGas: ?Gwei = null
difficulty: u256
extraData: Hex
gasLimit: Gwei
gasUsed: Gwei
hash: ?Hash
logsBloom: ?Hex
miner: Address
mixHash: ?Hash = null
nonce: ?u64
number: ?u64
parentHash: Hash
receiptsRoot: Hash
sealFields: ?[]const Hex = null
sha3Uncles: Hash
size: u64
stateRoot: Hash
timestamp: u64
totalDifficulty: ?u256 = null
transactions: ?BlockTransactions = null
transactionsRoot: Hash
uncles: ?[]const Hash = null
l1BlockNumber: u64
sendCount: u64
sendRoot: Hash
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

## BlockTransactions

Possible transactions that can be found in the
block struct fields.

### Properties

```zig
hashes: []const Hash
objects: []const Transaction
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
pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void
```

## BeaconBlock

Almost similar to `LegacyBlock` but with
the `withdrawalsRoot` and `withdrawals` fields.

### Properties

```zig
baseFeePerGas: ?Gwei
difficulty: u256
extraData: Hex
gasLimit: Gwei
gasUsed: Gwei
hash: ?Hash
logsBloom: ?Hex
miner: Address
mixHash: ?Hash = null
nonce: ?u64
number: ?u64
parentHash: Hash
receiptsRoot: Hash
sealFields: ?[]const Hex = null
sha3Uncles: Hash
size: u64
stateRoot: Hash
timestamp: u64
totalDifficulty: ?u256 = null
transactions: ?BlockTransactions = null
transactionsRoot: Hash
uncles: ?[]const Hash = null
withdrawalsRoot: Hash
withdrawals: []const Withdrawal
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

## BlobBlock

Almost similar to `BeaconBlock` but with this support blob fields

### Properties

```zig
baseFeePerGas: ?Gwei
blobGasUsed: Gwei
difficulty: u256
excessBlobGas: Gwei
extraData: Hex
gasLimit: Gwei
gasUsed: Gwei
hash: ?Hash
logsBloom: ?Hex
miner: Address
mixHash: ?Hash = null
nonce: ?u64
number: ?u64
parentBeaconBlockRoot: Hash
parentHash: Hash
receiptsRoot: Hash
sealFields: ?[]const Hex = null
sha3Uncles: Hash
size: u64
stateRoot: Hash
timestamp: u64
totalDifficulty: ?u256 = null
transactions: ?BlockTransactions = null
transactionsRoot: Hash
uncles: ?[]const Hash = null
withdrawalsRoot: Hash
withdrawals: []const Withdrawal
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

## Block

Union type of the possible blocks found on the network.

### Properties

```zig
beacon: BeaconBlock
legacy: LegacyBlock
cancun: BlobBlock
arbitrum: ArbitrumBlock
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
pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void
```

