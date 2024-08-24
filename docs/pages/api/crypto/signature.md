## Signature

Zig representation of an ethereum signature.

### Properties

```zig
r: [Secp256k1.scalar.encoded_length]u8
s: [Secp256k1.scalar.encoded_length]u8
v: u2
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
Converts the struct signature into a hex string.\
Caller owns the memory

### Signature

```zig
pub fn toHex(sig: Signature, allocator: Allocator) ![]u8
```

### FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) !Signature
```

## FromCompact
Converts a `CompactSignature` into a `Signature`.

### Signature

```zig
pub fn fromCompact(compact: CompactSignature) Signature
```

## ToBytes
Converts the struct signature into bytes.

### Signature

```zig
pub fn toBytes(sig: Signature) [65]u8
```

## ToHex
Converts the struct signature into a hex string.\
Caller owns the memory

### Signature

```zig
pub fn toHex(sig: Signature, allocator: Allocator) ![]u8
```

## FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) !Signature
```

## CompactSignature

Zig representation of a compact ethereum signature.

### Properties

```zig
r: [Secp256k1.scalar.encoded_length]u8
yParityWithS: [Secp256k1.scalar.encoded_length]u8
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
Converts the struct signature into a hex string.\
Caller owns the memory

### Signature

```zig
pub fn toHex(sig: CompactSignature, allocator: Allocator) ![]u8
```

### FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) CompactSignature
```

## ToCompact
Converts from a `Signature` into `CompactSignature`.

### Signature

```zig
pub fn toCompact(sig: Signature) CompactSignature
```

## ToBytes
Converts the struct signature into bytes.

### Signature

```zig
pub fn toBytes(sig: CompactSignature) [Secp256k1.scalar.encoded_length * 2]u8
```

## ToHex
Converts the struct signature into a hex string.\
Caller owns the memory

### Signature

```zig
pub fn toHex(sig: CompactSignature, allocator: Allocator) ![]u8
```

## FromHex
Converts a hex signature into it's struct representation.

### Signature

```zig
pub fn fromHex(hex: []const u8) CompactSignature
```

