# `Signature`

## Definition

This is essentially a wrapper for the signature that `libsecp256k1` uses.
Zabi supports both normal signatures and compact ones.

```zig
const Signature = struct {
  r: [Secp256k1.scalar.encoded_length]u8,
  s: [Secp256k1.scalar.encoded_length]u8,
  v: u2,
}
```

```zig
const CompactSignature = struct {
  r: [Secp256k1.scalar.encoded_length]u8,
  yParityWithS: [Secp256k1.scalar.encoded_length]u8,
}
```

## Usage

These types have some methods that can be used to convert from one to the other and to convert to `Bytes` or `Hex`.

## toCompact and fromCompact

Converts a `Signature` to a `CompactSignature` or vice versa.

:::code-group

```zig [signature.zig]
const sig: CompactSignature = .{
  .r = &[_]u8{0} ** 32,
  .yParityWithS = &[_]u8{0} ** 32,
}

try Signature.fromCompact(sig);

// Result
// const sig: Signature = .{
//  .r = &[_]u8{0} ** 32,
//  .s = &[_]u8{0} ** 32,
//  .v = 0
// }
```

```zig [compact.zig]
const sig: Signature = .{
 .r = &[_]u8{0} ** 32,
 .s = &[_]u8{0} ** 32,
 .v = 0
}

try CompactSignature.toCompact(sig);

// Result
// const sig: CompactSignature = .{
//  .r = &[_]u8{0} ** 32,
//  .yParityWithS = &[_]u8{0} ** 32,
// }
```
:::

## toBytes

Converts a `Signature` or `CompactSignature` to a `[65]u8` byte array.

:::code-group

```zig [signature.zig]
const sig: Signature = .{
 .r = &[_]u8{0} ** 32,
 .s = &[_]u8{0} ** 32,
 .v = 0
}

try sig.toBytes();
// Result
// [_]u8{0} ** 65

```

```zig [compact.zig]
const sig: CompactSignature = .{
  .r = &[_]u8{0} ** 32,
  .yParityWithS = &[_]u8{0} ** 32,
}

try sig.toBytes();
// Result
// [_]u8{0} ** 65
```
:::

## toHex

Converts a `Signature` or `CompactSignature` to a `Hex` string.

:::code-group

```zig [signature.zig]
const sig: Signature = .{
 .r = &[_]u8{0} ** 32,
 .s = &[_]u8{0} ** 32,
 .v = 0
}

try sig.toHex();
// Result
// &[_]u8{0} ** 130

```

```zig [compact.zig]
const sig: CompactSignature = .{
  .r = &[_]u8{0} ** 32,
  .yParityWithS = &[_]u8{0} ** 32,
}

try sig.toHex();
// Result
// &[_]u8{0} ** 130
```
:::

