## SerializeErrors

Set of possible errors when serializing a transaction.

```zig
RlpEncodeErrors || error{InvalidRecoveryId}
```

## SerializeTransaction
Main function to serialize transactions.

Supports cancun, london, berlin and legacy transaction envelopes.\
This uses the underlaying rlp encoding to serialize the transaction and takes an optional `Signature` in case
you want to serialize with the transaction signed.

For cancun transactions with blobs use the `serializeCancunTransactionWithBlobs` or `serializeCancunTransactionWithSidecars` functions.\

**Example**
```zig
const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
const base_legacy = try serializeTransaction(testing.allocator, .{
    .legacy = .{
        .nonce = 69,
        .gasPrice = try utils.parseGwei(2),
        .gas = 0,
        .to = to,
        .value = try utils.parseEth(1),
        .data = null,
    },
}, null);
defer testing.allocator.free(base_legacy);
```

### Signature

```zig
pub fn serializeTransaction(allocator: Allocator, tx: TransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## SerializeTransactionEIP7702
Function to serialize eip7702 transactions.
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionEIP7702(allocator: Allocator, tx: Eip7702TransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## SerializeCancunTransaction
Serializes a cancun type transactions without blobs.

Please use `serializeCancunTransactionWithSidecars` or
`serializeCancunTransactionWithBlobs` if you want to
serialize them as a wrapper.

### Signature

```zig
pub fn serializeCancunTransaction(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## SerializeCancunTransactionWithBlobs
Serializes a cancun sidecars into the eip4844 wrapper.

### Signature

```zig
pub fn serializeCancunTransactionWithBlobs(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature, blobs: []const Blob, trusted_setup: *KZG4844) ![]u8
```

## SerializeCancunTransactionWithSidecars
Serializes a cancun sidecars into the eip4844 wrapper.

### Signature

```zig
pub fn serializeCancunTransactionWithSidecars(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature, sidecars: Sidecars) ![]u8
```

## SerializeTransactionEIP1559
Function to serialize eip1559 transactions.
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionEIP1559(allocator: Allocator, tx: LondonTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## SerializeTransactionEIP2930
Function to serialize eip2930 transactions.
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionEIP2930(allocator: Allocator, tx: BerlinTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## SerializeTransactionLegacy
Function to serialize legacy transactions.
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionLegacy(allocator: Allocator, tx: LegacyTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8
```

## PrepareAccessList
Serializes the access list into a slice of tuples of hex values.

### Signature

```zig
pub fn prepareAccessList(allocator: Allocator, access_list: []const AccessList) Allocator.Error![]const StructToTupleType(AccessList)
```

## PrepareAuthorizationList
Serializes the authorization list into a slice of tuples of hex values.

### Signature

```zig
pub fn prepareAuthorizationList(allocator: Allocator, authorization_list: []const AuthorizationPayload) Allocator.Error![]const StructToTupleType(AuthorizationPayload)
```

