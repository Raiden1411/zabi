## RlpDecodeErrors

Set of errors while performing RLP decoding.

```zig
error{ UnexpectedValue, InvalidEnumTag, LengthMissmatch, Overflow } || Allocator.Error
```

## DecodeRlp
RLP decoding wrapper function. Encoded string must follow the RLP specification.

Supported types:
  * `bool`
  * `int`
  * `enum`, `enum_literal`
  * `null`
  * `?T`
  * `[N]T` array types.
  * `[]const T` slices.
  * `structs`. Both tuple and non tuples.

All other types are currently not supported.

### Signature

```zig
pub fn decodeRlp(comptime T: type, allocator: Allocator, encoded: []const u8) RlpDecodeErrors!T
```

## RlpDecoder

RLP Decoder structure. Decodes based on the RLP specification.

### Properties

```zig
struct {
  /// The RLP encoded slice.
  encoded: []const u8
  /// The position into the encoded slice.
  position: usize
}
```

### Init
Sets the decoder initial state.

### Signature

```zig
pub fn init(encoded: []const u8) RlpDecoder
```

### AdvancePosition
Advances the decoder position by `new` size.

### Signature

```zig
pub fn advancePosition(self: *RlpDecoder, new: usize) void
```

### Decode
Decodes a rlp encoded slice into a provided type.
The encoded slice must follow the RLP specification.

Supported types:
  * `bool`
  * `int`
  * `enum`, `enum_literal`
  * `null`
  * `?T`
  * `[N]T` array types.
  * `[]const T` slices.
  * `structs`. Both tuple and non tuples.

All other types are currently not supported.

### Signature

```zig
pub fn decode(self: *RlpDecoder, comptime T: type, allocator: Allocator) RlpDecodeErrors!T
```

