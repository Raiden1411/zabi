## RlpDecodeErrors

Set of errors while performing RLP decoding.

```zig
error{ UnexpectedValue, InvalidEnumTag, LengthMissmatch } || Allocator.Error || std.fmt.ParseIntError
```

## DecodeRlp
RLP decoding. Encoded string must follow the RLP specs.

### Signature

```zig
pub fn decodeRlp(allocator: Allocator, comptime T: type, encoded: []const u8) RlpDecodeErrors!T
```

