## RlpEncodeErrors

```zig
error{ NegativeNumber, Overflow } || Allocator.Error
```

## EncodeRlp
RLP Encoding. Items is expected to be a tuple of values.
Compilation will fail if you pass in any other type.
Caller owns the memory so it must be freed.

### Signature

```zig
pub fn encodeRlp(alloc: Allocator, items: anytype) ![]u8
```

