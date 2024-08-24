## DepositTransaction

### Properties

```zig
struct {
  sourceHash: Hash
  from: Address
  to: ?Address
  mint: u256
  value: Wei
  gas: Gwei
  isSystemTx: bool
  data: ?Hex
}
```

## DepositTransactionSigned

### Properties

```zig
struct {
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
}
```

## DepositData

### Properties

```zig
struct {
  mint: u256
  value: Wei
  gas: Gwei
  creation: bool
  data: ?Hex
}
```

## TransactionDeposited

### Properties

```zig
struct {
  from: Address
  to: Address
  version: u256
  opaqueData: Hex
  logIndex: usize
  blockHash: Hash
}
```

## DepositTransactionEnvelope

### Properties

```zig
struct {
  gas: ?Gwei = null
  mint: ?Wei = null
  value: ?Wei = null
  creation: bool = false
  data: ?Hex = null
  to: ?Address = null
}
```

