## QueryOptions

The block explorers api query options.

### Properties

```zig
/// The page number if pagination is enabled.
page: ?usize = null
/// The number of items displayed per page.
offset: ?usize = null
/// The prefered sorting sequence.
/// Asc for ascending and desc for descending.
sort: ?enum { asc, desc } = null
```

## SearchUrlParams
Writes the given value to the `std.io.Writer` stream.\
See `QueryWriter` for a more detailed documentation.

### Signature

```zig
pub fn searchUrlParams(value: anytype, options: QueryOptions, out_stream: anytype) @TypeOf(out_stream).Error!void
```

## SearchUrlParamsAlloc
Writes the given value to an `ArrayList` stream.\
This will allocated memory instead of writting to `std.io.Writer`.\
You will need to free the allocated memory.\
See `QueryWriter` for a more detailed documentation.

### Signature

```zig
pub fn searchUrlParamsAlloc(allocator: Allocator, value: anytype, options: QueryOptions) Allocator.Error![]u8
```

## WriteStream
See `QueryWriter` for a more detailed documentation.

### Signature

```zig
pub fn writeStream(out_stream: anytype) QueryWriter(@TypeOf(out_stream))
```

## QueryWriter
Essentially a wrapper for a `Writer` interface
specified for query parameters.\
The final expected sequence is something like: **"?foo=1&bar=2"**
Supported types:
  * Zig `bool` -> "true" or "false"
  * Zig `?T` -> "null" for null values or it renders `T` if it's supported.\
  * Zig `u32`, `i64`, etc -> the string representation of the number.\
  * Zig `floats` -> the string representation of the float.\
  * Zig `[N]u8` -> it assumes as a hex encoded string. For arrays of size 20,40,42 it will assume as a ethereum address.\
  * Zig `enum` -> the tagname of the enum.\
  * Zig `*T` -> the rending of T if it's supported.\
  * Zig `[]const u8` -> it writes it as a normal string.\
  * Zig `[]u8` -> it writes it as a hex encoded string.\
  * Zig `[]const T` -> the rendering of T if it's supported. Values are comma seperated in case
  of multiple values. It will not place the brackets on the query parameters.\
All other types are currently not supported.

### Signature

```zig
pub fn QueryWriter(comptime OutStream: type) type
```

## Stream

## Error

## Init
Start the writer initial state.

### Signature

```zig
pub fn init(stream: OutStream) Self
```

## BeginQuery
Start the begging of the query string.

### Signature

```zig
pub fn beginQuery(self: *Self) Error!void
```

## ValueOrParameterStart
Start either the parameter or value of the query string.

### Signature

```zig
pub fn valueOrParameterStart(self: *Self) Error!void
```

## ValueDone
Marks the current value as done.

### Signature

```zig
pub fn valueDone(self: *Self) void
```

## ParameterDone
Marks the current parameter as done.

### Signature

```zig
pub fn parameterDone(self: *Self) void
```

## WriteQueryOptions
Writes the query options into the `Stream`.\
It will only write non null values otherwise it will do nothing.

### Signature

```zig
pub fn writeQueryOptions(self: *Self, options: QueryOptions) Error!void
```

## WriteParameter
Writes a parameter of the query string.

### Signature

```zig
pub fn writeParameter(self: *Self, name: []const u8) Error!void
```

## WriteValue
Writes the value of the parameter of the query string.\
Not all types are accepted.

### Signature

```zig
pub fn writeValue(self: *Self, value: anytype) Error!void
```

