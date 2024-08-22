## QueryOptions
The block explorers api query options.

## SearchUrlParams
Writes the given value to the `std.io.Writer` stream.\
See `QueryWriter` for a more detailed documentation.

## SearchUrlParamsAlloc
Writes the given value to an `ArrayList` stream.\
This will allocated memory instead of writting to `std.io.Writer`.\
You will need to free the allocated memory.\
See `QueryWriter` for a more detailed documentation.

## WriteStream
See `QueryWriter` for a more detailed documentation.

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

## Stream

## Error

## Init
Start the writer initial state.

## BeginQuery
Start the begging of the query string.

## ValueOrParameterStart
Start either the parameter or value of the query string.

## ValueDone
Marks the current value as done.

## ParameterDone
Marks the current parameter as done.

## WriteQueryOptions
Writes the query options into the `Stream`.\
It will only write non null values otherwise it will do nothing.

## WriteParameter
Writes a parameter of the query string.

## WriteValue
Writes the value of the parameter of the query string.\
Not all types are accepted.

