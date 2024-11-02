## RlpEncoder
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
This also supports generating a `Writer` interface.

Supported types:
  * `bool`
  * `int`
  * `enum`, `enum_literal`
  * `error_set`,
  * `null`
  * `?T`
  * `[N]T` array types.
  * `[]const T` slices.
  * `*T` pointer types.
  * `structs`. Both tuple and non tuples.

All other types are currently not supported.

Depending on your use case you case use this in to ways.

Use `encodeNoList` if the type that you need to encode isn't a tuple, slice or array (doesn't apply for u8 slices and arrays.)
and use `encodeList` if you need to encode the above mentioned.

Only `encodeList` will allocate memory when using this interface.

### Signature

```zig
pub fn RlpEncoder(comptime OutWriter: type) type
```

## Error

Set of errors that can be produced when encoding values.

```zig
OutWriter.Error || error{ Overflow, NegativeNumber }
```

## Writer

The writer interface that can rlp encode.

```zig
std.io.Writer(*Self, Error, encodeString)
```

## RlpSizeTag

Value that are used to identifity the size depending on the type

### Properties

```zig
enum {
  number = 0x80
  string = 0xb7
  list = 0xf7
}
```

## Init
Sets the initial state.

### Signature

```zig
pub fn init(stream: OutWriter) Self
```

## EncodeNoList
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
For non `u8` slices and arrays use `encodeList`. Same applies for tuples and structs.

### Signature

```zig
pub fn encodeNoList(self: *Self, payload: anytype) Error!void
```

## EncodeList
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).
Only use this if you payload contains a slice, array or tuple/struct.

This will allocate memory because it creates a `ArrayList` writer for the recursive calls.

### Signature

```zig
pub fn encodeList(self: *Self, allocator: Allocator, payload: anytype) Error!void
```

## EncodeString
Performs RLP encoding on a "string" type.

For more information please check the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).

### Signature

```zig
pub fn encodeString(self: *Self, slice: []const u8) Error!void
```

## WriteSize
Finds the bit size of the passed number and writes it to the stream.

Example:
```zig
const slice = "dog";

try rlp_encoder.writeSize(usize, slice.len, .number);
// Encodes as 0x80 + slice.len

try rlp_encoder.writeSize(usize, slice.len, .string);
// Encodes as 0xb7 + slice.len

try rlp_encoder.writeSize(usize, slice.len, .list);
// Encodes as 0xf7 + slice.len
```

### Signature

```zig
pub fn writeSize(self: *Self, comptime T: type, number: T, tag: RlpSizeTag) Error!void
```

## Writer
RLP encoding writer interface.

### Signature

```zig
pub fn writer(self: *Self) Writer
```

## EncodeRlp
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).

Supported types:
  * `bool`
  * `int`
  * `enum`, `enum_literal`
  * `error_set`,
  * `null`
  * `?T`
  * `[N]T` array types.
  * `[]const T` slices.
  * `*T` pointer types.
  * `structs`. Both tuple and non tuples.

All other types are currently not supported.

**Example**
```zig
const encoded = try encodeRlp(allocator, 69420);
defer allocator.free(encoded);
```

### Signature

```zig
pub fn encodeRlp(allocator: Allocator, payload: anytype) RlpEncoder(ArrayListWriter).Error![]u8
```

## EncodeRlpFromArrayListWriter
RLP Encoding according to the [spec](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/).

Supported types:
  * `bool`
  * `int`
  * `enum`, `enum_literal`
  * `error_set`,
  * `null`
  * `?T`
  * `[N]T` array types.
  * `[]const T` slices.
  * `*T` pointer types.
  * `structs`. Both tuple and non tuples.

All other types are currently not supported.

**Example**
```zig
var list = std.ArrayList(u8).init(allocator);
errdefer list.deinit();

try encodeRlpFromArrayListWriter(allocator, 69420, list);
const encoded = try list.toOwnedSlice();
```

### Signature

```zig
pub fn encodeRlpFromArrayListWriter(allocator: Allocator, payload: anytype, list: ArrayListWriter) RlpEncoder(ArrayListWriter).Error!void
```

