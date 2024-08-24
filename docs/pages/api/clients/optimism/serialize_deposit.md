## SerializeDepositTransaction
Serializes an OP deposit transaction
Caller owns the memory

### Signature

```zig
pub fn serializeDepositTransaction(allocator: Allocator, tx: DepositTransaction) ![]u8
```

