## LogDecoderOptions

Set of options that can alter the decoder behaviour.

## DecodeLogs
Decodes the abi encoded slice. This will ensure that the provided type
is always a tuple struct type and that the first member type is a [32]u8 type.\
No allocations are made unless you want to create a pointer type and provide the optional
allocator.\
**Example:**
```zig
const encodeds = try decodeLogs(
    struct { [32]u8 },
    &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")},
    .{},
);
```

### Signature

```zig
pub fn decodeLogs(comptime T: type, encoded: []const ?Hash, options: LogDecoderOptions) !T
```

## DecodeLog
Decodes the abi encoded bytes. Not all types are supported.\
Bellow there is a list of supported types.\
Supported:
    - Bool, Int, Optional, Arrays, Pointer.\
For Arrays only u8 child types are supported and must be 32 or lower of length.\
For Pointer types the pointers on `One` size are supported. All other are unsupported.\
**Example:**
```zig
const decoded = try decodeLog(u256, try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0"), .{});
```

### Signature

```zig
pub fn decodeLog(comptime T: type, encoded: Hash, options: LogDecoderOptions) !T
```

