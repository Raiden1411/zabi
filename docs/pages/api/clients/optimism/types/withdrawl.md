## Message

## WithdrawalRequest

### Properties

```zig
data: ?Hex = null
gas: ?Gwei = null
to: Address
value: ?Wei = null
```

## PreparedWithdrawal

### Properties

```zig
data: Hex
gas: Gwei
to: Address
value: Wei
```

## Withdrawal

### Properties

```zig
nonce: Wei
sender: Address
target: Address
value: Wei
gasLimit: Wei
data: Hex
withdrawalHash: Hash
```

## WithdrawalNoHash

## WithdrawalRootProof

### Properties

```zig
version: Hash
stateRoot: Hash
messagePasserStorageRoot: Hash
latestBlockhash: Hash
```

## Proofs

### Properties

```zig
outputRootProof: WithdrawalRootProof
withdrawalProof: []const Hex
l2OutputIndex: u256
```

## WithdrawalEnvelope

## ProvenWithdrawal

### Properties

```zig
outputRoot: Hash
timestamp: u128
l2OutputIndex: u128
```

## Game

### Properties

```zig
index: u256
metadata: Hash
timestamp: u64
rootClaim: Hash
extraData: Hex
```

## GameResult

### Properties

```zig
index: u256
metadata: Hash
timestamp: u64
rootClaim: Hash
l2BlockNumber: u256
```

## NextGameTimings

### Properties

```zig
interval: i64
seconds: i64
timestamp: ?i64
```

