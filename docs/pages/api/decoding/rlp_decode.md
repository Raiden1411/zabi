## RlpDecodeErrors

```zig
error{ UnexpectedValue, InvalidEnumTag } || Allocator.Error || std.fmt.ParseIntError
```

## DecodeRlp
RLP decoding. Encoded string must follow the RLP specs.

### Signature

```zig
pub fn decodeRlp(allocator: Allocator, comptime T: type, encoded: []const u8) !T
```

