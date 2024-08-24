## Message

### Properties

```zig
struct {
  blockNumber: u64
  messages: []const Withdrawal
}
```

## WithdrawalRequest

### Properties

```zig
struct {
  data: ?Hex = null
  gas: ?Gwei = null
  to: Address
  value: ?Wei = null
}
```

## PreparedWithdrawal

### Properties

```zig
struct {
  data: Hex
  gas: Gwei
  to: Address
  value: Wei
}
```

## Withdrawal

### Properties

```zig
struct {
  nonce: Wei
  sender: Address
  target: Address
  value: Wei
  gasLimit: Wei
  data: Hex
  withdrawalHash: Hash
}
```

## WithdrawalNoHash

```zig
Omit(Withdrawal, &.{"withdrawalHash"})
```

## WithdrawalRootProof

### Properties

```zig
struct {
  version: Hash
  stateRoot: Hash
  messagePasserStorageRoot: Hash
  latestBlockhash: Hash
}
```

## Proofs

### Properties

```zig
struct {
  outputRootProof: WithdrawalRootProof
  withdrawalProof: []const Hex
  l2OutputIndex: u256
}
```

## WithdrawalEnvelope

```zig
MergeStructs(WithdrawalNoHash, Proofs)
```

## ProvenWithdrawal

### Properties

```zig
struct {
  outputRoot: Hash
  timestamp: u128
  l2OutputIndex: u128
}
```

## Game

### Properties

```zig
struct {
  index: u256
  metadata: Hash
  timestamp: u64
  rootClaim: Hash
  extraData: Hex
}
```

## GameResult

### Properties

```zig
struct {
  index: u256
  metadata: Hash
  timestamp: u64
  rootClaim: Hash
  l2BlockNumber: u256
}
```

## NextGameTimings

### Properties

```zig
struct {
  interval: i64
  seconds: i64
  timestamp: ?i64
}
```

