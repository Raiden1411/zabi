## ParamErrors

Set of errors when converting `[]const u8` into `ParamType`.

```zig
error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Allocator.Error
```

## FixedArray

Representation of the solidity fixed array type.

### Properties

```zig
struct {
  child: *const ParamType
  size: usize
}
```

## ParamType

Type that represents solidity types in zig.

### Properties

```zig
union(enum) {
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
}
```

### FromHumanReadableTokenTag
Converts a human readable token into `ParamType`.

### Signature

```zig
pub fn fromHumanReadableTokenTag(tag: TokenTags) ?ParamType
```

### FreeArrayParamType
User must call this if the union type contains a fixedArray or dynamicArray field.
They create pointers so they must be destroyed after.

### Signature

```zig
pub fn freeArrayParamType(self: @This(), alloc: Allocator) void
```

### TypeToJsonStringify
Converts the tagname of `self` into a writer.

### Signature

```zig
pub fn typeToJsonStringify(self: @This(), writer: anytype) @TypeOf(writer).Error!void
```

### TypeToString
Converts `self` into its tagname.

### Signature

```zig
pub fn typeToString(self: @This(), writer: anytype) @TypeOf(writer).Error!void
```

### TypeToUnion
Helper function that is used to convert solidity types into zig unions,
the function will allocate if a array or a fixed array is used.

Consider using `freeArrayParamType` to destroy the pointers
or call the destroy method on your allocator manually

### Signature

```zig
pub fn typeToUnion(abitype: []const u8, alloc: Allocator) ParamErrors!ParamType
```

### TypeToUnionWithTag
### Signature

```zig
pub fn typeToUnionWithTag(allocator: Allocator, abitype: []const u8, token_tag: TokenTags) ParamErrors!ParamType
```

