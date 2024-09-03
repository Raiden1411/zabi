## RlpEncodeErrors

Set of errors while performing rlp encoding.

```zig
error{ NegativeNumber, Overflow } || Allocator.Error
```

## EncodeRlp
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).

Reflects on the items and encodes based on it's type.\
Supports almost all of zig's type.

Doesn't support `opaque`, `fn`, `anyframe`, `error_union`, `void`, `null` types.

**Example**
```zig
const encoded = try encodeRlp(allocator, 69420);
defer allocator.free(encoded);
```

### Signature

```zig
pub fn encodeRlp(allocator: Allocator, payload: anytype) RlpEncodeErrors![]u8
```

