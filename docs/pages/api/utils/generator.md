## Generated
Similar to std.json.Parsed(T)

### Signature

```zig
pub fn Generated(comptime T: type) type
```

## Deinit
### Signature

```zig
pub fn deinit(self: @This()) void
```

## GenerateOptions

Controls some of the behaviour for the generator.

More options can be added in the future to alter
further this behaviour.

### Properties

```zig
struct {
  /// Control the size of the slice that you want to create.
  slice_size: ?usize = null
  /// If the provided type is consider a potential "string"
  /// Tell the generator to use only ascii letter bytes and
  /// if you want lower or uppercase chars
  ascii: struct {
        use_on_arrays_and_slices: bool = false,
        format_bytes: enum { lowercase, uppercase } = .lowercase,
    } = .{}
  /// Tell the generator to use the types default values.
  use_default_values: bool = false
}
```

## GenerateRandomData
Generate pseudo random data for the provided type. Creates an
arena for all allocations. Similarly to how std.json works.

This works on most zig types with a few expections of course.

### Signature

```zig
pub fn generateRandomData(comptime T: type, allocator: Allocator, seed: u64, opts: GenerateOptions) Allocator.Error!Generated(T)
```

## GenerateRandomDataLeaky
Generate pseudo random data for provided type. Nothing is freed
from the result so it's best to use something like an arena allocator or similar
to free the memory all at once.

This is done because we might have
types where there will be deeply nested allocatations that can
be cumbersome to free.

This works on most zig types with a few expections of course.

### Signature

```zig
pub fn generateRandomDataLeaky(comptime T: type, allocator: Allocator, seed: u64, opts: GenerateOptions) Allocator.Error!T
```

