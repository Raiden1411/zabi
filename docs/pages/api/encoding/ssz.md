## EncodeSSZ
Performs ssz encoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).
Almost all zig types are supported.

Caller owns the memory

### Signature

```zig
pub fn encodeSSZ(allocator: Allocator, value: anytype) ![]u8
```

