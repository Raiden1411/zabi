## SerializeTransaction
Main function to serialize transactions.\
Support london, berlin and legacy transaction envelopes.\
For cancun transactions with blobs use the `serializeCancunTransactionWithBlob` function. This
will panic if you call this with the cancun transaction envelope.\
Caller ownes the memory

### Signature

```zig
pub fn serializeTransaction(allocator: Allocator, tx: TransactionEnvelope, sig: ?Signature) ![]u8
```

## SerializeCancunTransaction
Serializes a cancun type transactions without blobs.\
Please use `serializeCancunTransactionWithSidecars` or
`serializeCancunTransactionWithBlobs` if you want to
serialize them as a wrapper

### Signature

```zig
pub fn serializeCancunTransaction(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature) ![]u8
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
Function to serialize eip1559 transactions.\
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionEIP1559(allocator: Allocator, tx: LondonTransactionEnvelope, sig: ?Signature) ![]u8
```

## SerializeTransactionEIP2930
Function to serialize eip2930 transactions.\
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionEIP2930(allocator: Allocator, tx: BerlinTransactionEnvelope, sig: ?Signature) ![]u8
```

## SerializeTransactionLegacy
Function to serialize legacy transactions.\
Caller ownes the memory

### Signature

```zig
pub fn serializeTransactionLegacy(allocator: Allocator, tx: LegacyTransactionEnvelope, sig: ?Signature) ![]u8
```

## PrepareAccessList
Serializes the access list into a slice of tuples of hex values.

### Signature

```zig
pub fn prepareAccessList(allocator: Allocator, access_list: []const AccessList) ![]const StructToTupleType(AccessList)
```

