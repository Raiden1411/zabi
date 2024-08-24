## ParamErrors

```zig
error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Allocator.Error
```

## FixedArray

## ParamType

### Properties

```zig
address
string
bool
bytes
tuple
uint: usize
int: usize
fixedBytes: usize
@"enum": usize
fixedArray: FixedArray
dynamicArray: *const ParamType
```

### FreeArrayParamType
User must call this if the union type contains a fixedArray or dynamicArray field.\
They create pointers so they must be destroyed after.

### Signature

```zig
pub fn freeArrayParamType(self: @This(), alloc: Allocator) void
```

### JsonParse
Overrides the `jsonParse` from `std.json`.\
We do this because a union is treated as expecting a object string in Zig.\
But since we are expecting a string that contains the type value
we override this so we handle the parsing properly and still leverage the union type.

### Signature

```zig
pub fn jsonParse(alloc: Allocator, source: *Scanner, opts: ParserOptions) !ParamType
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(alloc: Allocator, source: std.json.Value, opts: ParserOptions) !ParamType
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void
```

### TypeToJsonStringify
### Signature

```zig
pub fn typeToJsonStringify(self: @This(), writer: anytype) !void
```

### TypeToString
### Signature

```zig
pub fn typeToString(self: @This(), writer: anytype) !void
```

### TypeToUnion
Helper function that is used to convert solidity types into zig unions,
the function will allocate if a array or a fixed array is used.\
Consider using `freeArrayParamType` to destroy the pointers
or call the destroy method on your allocator manually

### Signature

```zig
pub fn typeToUnion(abitype: []const u8, alloc: Allocator) !ParamType
```

