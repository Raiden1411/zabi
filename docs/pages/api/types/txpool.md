## TxPoolStatus

Result tx pool status.

### Properties

```zig
struct {
  pending: u64
  queued: u64
}
```

## TxPoolContent

Result tx pool content.

### Properties

```zig
struct {
  pending: Subpool
  queued: Subpool
}
```

## TxPoolInspect

### Properties

```zig
struct {
  pending: InspectSubpool
  queued: InspectSubpool
}
```

## Subpool

Geth mempool subpool type

### Properties

```zig
struct {
  address: AddressHashMap
}
```

## InspectSubpool

Geth mempool inspect subpool type

### Properties

```zig
struct {
  address: InspectAddressHashMap
}
```

## InspectPoolTransactionByNonce

Geth inspect transaction object dump from mempool by nonce.

### Properties

```zig
struct {
  nonce: InspectPoolPendingTransactionHashMap
}
```

## PoolTransactionByNonce

Geth transaction object dump from mempool by nonce.

### Properties

```zig
struct {
  nonce: PoolPendingTransactionHashMap
}
```

