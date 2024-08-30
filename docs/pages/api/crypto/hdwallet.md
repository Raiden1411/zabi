## HDWalletNode

Implementation of BIP32 HDWallets
It doesnt have support yet for extended keys.

### Properties

```zig
struct {
  /// The nodes private key that is used to derive the childs private keys.
  priv_key: [32]u8
  /// The compressed sec1 public key.
  pub_key: [33]u8
  /// The chain code that is used to derive public keys.
  chain_code: [32]u8
}
```

### FromSeed
Derive a node from a mnemonic seed. Use `pbkdf2` to generate the seed.

### Signature

```zig
pub fn fromSeed(seed: [64]u8) !Node
```

### FromSeedAndPath
Derive a node from a mnemonic seed and path. Use `pbkdf2` to generate the seed.
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

### Signature

```zig
pub fn fromSeedAndPath(seed: [64]u8, path: []const u8) !Node
```

### DerivePath
Derives a child node from a path.
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

### Signature

```zig
pub fn derivePath(self: Node, path: []const u8) !Node
```

### DeriveChild
Derive a child node based on the index
If the index is higher than std.math.maxInt(u32) this will error.

### Signature

```zig
pub fn deriveChild(self: Node, index: u32) !Node
```

### CastrateNode
Castrates a HDWalletNode. This essentially returns the node without the private key.

### Signature

```zig
pub fn castrateNode(self: Node) EunuchNode
```

## EunuchNode

The EunuchNode doesn't have the private field but it
can still be used to derive public keys and chain codes.

### Properties

```zig
struct {
  /// The compressed sec1 public key.
  pub_key: [33]u8
  /// The chain code that is used to derive public keys.
  chain_code: [32]u8
}
```

### DeriveChild
Derive a child node based on the index
If the index is higher than std.math.maxInt(u32) this will error.
EunuchWalletNodes cannot derive hardned nodes.

### Signature

```zig
pub fn deriveChild(self: Node, index: u32) !Node
```

### DerivePath
Derives a child node from a path. This cannot derive hardned nodes.
The path must follow the specification. Example: m/44/60/0/0/0 (Most common for ethereum)

### Signature

```zig
pub fn derivePath(self: Node, path: []const u8) !Node
```

