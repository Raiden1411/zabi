## ParseArgs
Parses console arguments in the style of --foo=bar
For now not all types are supported but might be in the future
if the need for them arises.

Allocations are only made for slices and pointer types.
Slice or arrays that aren't u8 are expected to be comma seperated.

### Signature

```zig
pub fn parseArgs(comptime T: type, allocator: Allocator, args: *std.process.ArgIterator) T
```

