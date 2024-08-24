## JsonParse
Custom jsonParse that is mostly used to enable
the ability to parse hex string values into native `int` types,
since parsing hex values is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonParse method for structs

### Signature

```zig
pub fn jsonParse(comptime T: type, allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!T
```

## JsonParseFromValue
Custom jsonParseFromValue that is mostly used to enable
the ability to parse hex string values into native `int` types,
since parsing hex values is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonParseFromValue method for structs

### Signature

```zig
pub fn jsonParseFromValue(comptime T: type, allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!T
```

## JsonStringify
Custom jsonStringify that is mostly used to enable
the ability to parse int values as hex and to parse address with checksum
and to treat array and slices of `u8` as hex encoded strings. This doesn't
apply if the slice is `const`.\
Parsing hex values or dealing with strings like this is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonStringify method for structs

### Signature

```zig
pub fn jsonStringify(comptime T: type, self: T, writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## InnerParseValueRequest
Inner parser that enables the behaviour described above.\
We don't use the `innerParse` from slice because the slice is get parsed
as a json dynamic `Value`.

### Signature

```zig
pub fn innerParseValueRequest(comptime T: type, allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!T
```

## InnerStringify
Inner stringifier that enables the behaviour described above.

### Signature

```zig
pub fn innerStringify(value: anytype, stream_writer: anytype) !void
```

