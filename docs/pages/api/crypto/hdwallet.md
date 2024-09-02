## DerivePathErrors

```zig
std.fmt.ParseIntError || DeriveChildErrors || error{InvalidPath}
```

## DeriveChildErrors

```zig
EncodingError || NonCanonicalError || NotSquareError || IdentityElementError
```

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
pub fn fromSeed(seed: [64]u8) IdentityElementError!Node
```

### FromSeedAndPath
Derive a node from a mnemonic seed and path. Use `pbkdf2` to generate the seed.\
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

**Example**
```zig
const seed = "test test test test test test test test test test test junk";
var hashed: [64]u8 = undefined;
try std.crypto.pwhash.pbkdf2(&hashed, seed, "mnemonic", 2048, HmacSha512);

const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/0");

const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
defer testing.allocator.free(hex);

try testing.expectEqualStrings("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", hex);
```

### Signature

```zig
pub fn fromSeedAndPath(seed: [64]u8, path: []const u8) DerivePathErrors!Node
```

### DerivePath
Derives a child node from a path.\
The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)

### Signature

```zig
pub fn derivePath(self: Node, path: []const u8) DerivePathErrors!Node
```

### DeriveChild
Derive a child node based on the index.\
If the index is higher than std.math.maxInt(u32) this will error.

### Signature

```zig
pub fn deriveChild(self: Node, index: u32) DeriveChildErrors!Node
```

### CastrateNode
Castrates a HDWalletNode. This essentially returns the node without the private key.

### Signature

```zig
pub fn castrateNode(self: Node) EunuchNode
```

## EunuchNode

The `EunuchNode` doesn't have the private field but it
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
Derive a child node based on the index.\
If the index is higher than std.math.maxInt(u32) this will error.

`EunuchNodes` cannot derive hardned nodes.

### Signature

```zig
pub fn deriveChild(self: Node, index: u32) (DeriveChildErrors || error{InvalidIndex})!Node
```

### DerivePath
Derives a child node from a path. This cannot derive hardned nodes.

The path must follow the specification. Example: m/44/60/0/0/0 (Most common for ethereum)

### Signature

```zig
pub fn derivePath(self: Node, path: []const u8) (DerivePathErrors || error{InvalidIndex})!Node
```

