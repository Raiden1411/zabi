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

