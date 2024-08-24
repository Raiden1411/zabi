## DecodeSSZ
Performs ssz decoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).

### Signature

```zig
pub fn decodeSSZ(comptime T: type, serialized: []const u8) !T
```

