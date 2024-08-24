## L2Output

### Properties

```zig
struct {
  outputIndex: u256
  outputRoot: Hash
  timestamp: u128
  l2BlockNumber: u128
}
```

## Domain

### Properties

```zig
enum {
  user_deposit = 0
  l1_info_deposit = 1
}
```

## GetDepositArgs

### Properties

```zig
struct {
  from: Address
  to: ?Address
  /// This expects that the data has already been hex decoded
  opaque_data: Hex
  domain: Domain
  log_index: u256
  l1_blockhash: Hash
  source_hash: ?Hash = null
}
```

