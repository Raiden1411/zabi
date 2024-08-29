## BlockTag

Block tag used for RPC requests.

### Properties

```zig
enum {
  latest
  earliest
  pending
  safe
  finalized
}
```

## BalanceBlockTag

Specific tags used in some RPC requests

```zig
Extract(BlockTag, "latest,pending,earliest")
```

## ProofBlockTag

Specific tags used in some RPC requests

```zig
Extract(BlockTag, "latest,earliest")
```

## BlockRequest

Used in the RPC method requests

### Properties

```zig
struct {
  block_number: ?u64 = null
  tag: ?BlockTag = .latest
  include_transaction_objects: ?bool = false
}
```

## BlockHashRequest

Used in the RPC method requests

### Properties

```zig
struct {
  block_hash: Hash
  include_transaction_objects: ?bool = false
}
```

## BalanceRequest

Used in the RPC method requests

### Properties

```zig
struct {
  address: Address
  block_number: ?u64 = null
  tag: ?BalanceBlockTag = .latest
}
```

## BlockNumberRequest

Used in the RPC method requests

### Properties

```zig
struct {
  block_number: ?u64 = null
  tag: ?BalanceBlockTag = .latest
}
```

## Withdrawal

Withdrawal field struct type.

### Properties

```zig
struct {
  index: u64
  validatorIndex: u64
  address: Address
  amount: Wei
}
```

## LegacyBlock

The most common block that can be found before the
ethereum merge. Doesn't contain the `withdrawals` or
`withdrawalsRoot` fields.

### Properties

```zig
struct {
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
}
```

## ArbitrumBlock

The most common block that can be found before the
ethereum merge. Doesn't contain the `withdrawals` or
`withdrawalsRoot` fields.

### Properties

```zig
struct {
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
}
```

## BlockTransactions

Possible transactions that can be found in the
block struct fields.

### Properties

```zig
union(enum) {
  hashes: []const Hash
  objects: []const Transaction
}
```

## BeaconBlock

Almost similar to `LegacyBlock` but with
the `withdrawalsRoot` and `withdrawals` fields.

### Properties

```zig
struct {
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
}
```

## BlobBlock

Almost similar to `BeaconBlock` but with this support blob fields

### Properties

```zig
struct {
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
  parentBeaconBlockRoot: ?Hash = null
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
  withdrawalsRoot: ?Hash = null
  withdrawals: ?[]const Withdrawal = null
}
```

## Block

Union type of the possible blocks found on the network.

### Properties

```zig
union(enum) {
  beacon: BeaconBlock
  legacy: LegacyBlock
  cancun: BlobBlock
  arbitrum: ArbitrumBlock
}
```

