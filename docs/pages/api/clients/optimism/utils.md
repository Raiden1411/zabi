## OpaqueToDepositData
This expects that the data was already decoded from hex

### Signature

```zig
pub fn opaqueToDepositData(hex_bytes: Hex) DepositData
```

## GetWithdrawalHashStorageSlot
Gets the storage hash from a message hash

### Signature

```zig
pub fn getWithdrawalHashStorageSlot(hash: Hash) Hash
```

## GetSourceHash
Gets the source hash from deposit transaction.

### Signature

```zig
pub fn getSourceHash(domain: Domain, log_index: u256, l1_blockhash: Hash) Hash
```

## GetDepositTransaction
Gets a deposit transaction based on the provided arguments.

### Signature

```zig
pub fn getDepositTransaction(opts: GetDepositArgs) DepositTransaction
```

## GetL2HashFromL1DepositInfo
Gets a L2 transaction hash from a deposit transaction.

### Signature

```zig
pub fn getL2HashFromL1DepositInfo(allocator: Allocator, opts: GetDepositArgs) !Hash
```

