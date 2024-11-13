## SchnorrSignature

Zig representation of an bip0340 schnorr signature.

### Properties

```zig
struct {
  r: [32]u8
  s: [32]u8
}
```

### ToBytes
Converts the struct signature into bytes.

### Signature

```zig
pub fn toBytes(sig: SchnorrSignature) [64]u8
```

### FromBytes
Converts the signature bytes into the struct.

### Signature

```zig
pub fn fromBytes(sig: [64]u8) SchnorrSignature
```

### ToHex
Converts the struct signature into a hex string.

Caller owns the memory

### Signature

```zig
pub fn toHex(sig: SchnorrSignature, allocator: Allocator) Allocator.Error![]u8
```

### FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) error{ NoSpaceLeft, InvalidSignature, InvalidLength, InvalidCharacter }!SchnorrSignature
```

## Signature

Zig representation of an ethereum signature.

### Properties

```zig
struct {
  r: u256
  s: u256
  v: u2
}
```

### FromCompact
Converts a `CompactSignature` into a `Signature`.

### Signature

```zig
pub fn fromCompact(compact: CompactSignature) Signature
```

### ToBytes
Converts the struct signature into bytes.

### Signature

```zig
pub fn toBytes(sig: Signature) [65]u8
```

### ToHex
Converts the struct signature into a hex string.

Caller owns the memory

### Signature

```zig
pub fn toHex(sig: Signature, allocator: Allocator) Allocator.Error![]u8
```

### FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) error{ NoSpaceLeft, InvalidSignature, InvalidLength, InvalidCharacter }!Signature
```

## CompactSignature

Zig representation of a compact ethereum signature.

### Properties

```zig
struct {
  r: u256
  yParityWithS: u256
}
```

### ToCompact
Converts from a `Signature` into `CompactSignature`.

### Signature

```zig
pub fn toCompact(sig: Signature) CompactSignature
```

### ToBytes
Converts the struct signature into bytes.

### Signature

```zig
pub fn toBytes(sig: CompactSignature) [Secp256k1.scalar.encoded_length * 2]u8
```

### ToHex
Converts the struct signature into a hex string.

Caller owns the memory

### Signature

```zig
pub fn toHex(sig: CompactSignature, allocator: Allocator) Allocator.Error![]u8
```

### FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) error{ NoSpaceLeft, InvalidSignature, InvalidLength, InvalidCharacter }!CompactSignature
```

