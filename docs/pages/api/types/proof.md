## ProofRequest

Eth get proof rpc request.

### Properties

```zig
struct {
  address: Address
  storageKeys: []const Hash
  blockNumber: ?u64 = null
}
```

## ProofResult

Result of eth_getProof

### Properties

```zig
struct {
  address: Address
  balance: Wei
  codeHash: Hash
  nonce: u64
  storageHash: Hash
  /// Array of RLP-serialized MerkleTree-Nodes
  accountProof: []const Hex
  storageProof: []const StorageProof
}
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## StorageProof

### Properties

```zig
struct {
  key: Hash
  value: Wei
  /// Array of RLP-serialized MerkleTree-Nodes
  proof: []const Hex
}
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

