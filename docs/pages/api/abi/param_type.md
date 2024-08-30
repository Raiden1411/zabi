## ParamErrors

```zig
error{ InvalidEnumTag, InvalidCharacter, LengthMismatch, Overflow } || Allocator.Error
```

## FixedArray

### Properties

```zig
struct {
  child: *const ParamType
  size: usize
}
```

## ParamType

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

### FreeArrayParamType
User must call this if the union type contains a fixedArray or dynamicArray field.
They create pointers so they must be destroyed after.

### Signature

```zig
pub fn freeArrayParamType(self: @This(), alloc: Allocator) void
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
the function will allocate if a array or a fixed array is used.

Consider using `freeArrayParamType` to destroy the pointers
or call the destroy method on your allocator manually

### Signature

```zig
pub fn typeToUnion(abitype: []const u8, alloc: Allocator) !ParamType
```

