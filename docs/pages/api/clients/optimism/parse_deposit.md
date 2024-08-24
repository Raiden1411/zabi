## ParseDepositTransaction
Parses a deposit transaction into its zig type
Only the data field will have allocated memory so you must free it after

### Signature

```zig
pub fn parseDepositTransaction(allocator: Allocator, encoded: []u8) !DepositTransaction
```

