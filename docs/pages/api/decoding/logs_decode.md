## LogDecoderOptions

Set of options that can alter the decoder behaviour.

### Properties

```zig
struct {
  /// Optional allocation in the case that you want to create a pointer
  /// That pointer must be destroyed later.
  allocator: ?Allocator = null
  /// Tells the endianess of the bytes that you want to decode
  /// Addresses are encoded in big endian and bytes1..32 are encoded in little endian.
  /// There might be some cases where you will need to decode a bytes20 and address at the same time.
  /// Since they can represent the same type it's advised to decode the address as `u160` and change this value to `little`.
  /// since it already decodes as big-endian and then `std.mem.writeInt` the value to the expected endianess.
  bytes_endian: Endian = .big
}
```

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

