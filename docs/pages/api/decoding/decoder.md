## DecoderErrors

Set of possible errors when the decoder runs.

```zig
error{ NoJunkDataAllowed, BufferOverrun, InvalidBitFound } || Allocator.Error
```

## DecodeOptions

Set of options to control the abi decoder behaviour.

## Decoded
Result type of decoded objects.

### Signature

```zig
pub fn Decoded(comptime T: type) type
```

## AbiDecoded
Result type of a abi decoded slice. Allocations are managed via an arena.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn AbiDecoded(comptime T: type) type
```

## Deinit
### Signature

```zig
pub fn deinit(self: @This()) void
```

## DecodeAbiFunction
Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.\
Assumes that the encoded slice contains the function signature and removes it from the
encoded slice.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
const decoded =  try decodeAbiFunction([]const i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn decodeAbiFunction(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T)
```

## DecodeAbiError
Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.\
Assumes that the encoded slice contracts the error signature and removes it from the
encoded slice.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
const decoded =  try decodeAbiError([]const i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn decodeAbiError(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T)
```

## DecodeAbiFunctionOutputs
Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.\
Since abi encoded function output values don't have signature in the encoded slice this is essentially a wrapper for `decodeAbiParameter`.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
const decoded =  try decodeAbiFunctionOutputs([]const i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn decodeAbiFunctionOutputs(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T)
```

## DecodeAbiConstructor
Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.\
Since abi encoded constructor values don't have signature in the encoded slice this is essentially a wrapper for `decodeAbiParameter`.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
const decoded =  try decodeAbiConstructor([]const i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn decodeAbiConstructor(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!AbiDecoded(T)
```

## DecodeAbiParameter
Decodes the abi encoded slice. All allocations are managed in an `ArenaAllocator`.\
This is usefull when you have to grab ownership of the memory from the slice or the type you need requires the creation
of an `ArrayList`.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000");
const decoded =  try decodeParameter([]const i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```
If the type provided doesn't make allocations consider using `decodeAbiParameterLeaky`.

### Signature

```zig
pub fn decodeAbiParameter(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) !AbiDecoded(T)
```

## DecodeAbiParameterLeaky
Decodes the abi encoded slice. This doesn't clean any allocated memory.\
Usefull if the type that you want do decode to doesn't create any allocations or you already
own the memory that this will decode from. Otherwise you will be better off using `decodeAbiParameter`.\
Allocations:
    `Bool`, `Int`, `Enum`, `Array` => **false**.\
    `Pointer` => **true**. If the child is `u8` only allocates if the option `alloc_always` is passed.\
    `Optional` => Depends on the child.\
    `Struct` => Depends on the child.\
    Other types are not supported.\
**Example:**
```zig
var buffer: [1024]u8 = undefined;
const bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002");
const decoded =  try decodeParameter([2]i256, testing.allocator, bytes, .{});
defer decoded.deinit();
```

### Signature

```zig
pub fn decodeAbiParameterLeaky(comptime T: type, allocator: Allocator, encoded: []u8, options: DecodeOptions) DecoderErrors!T
```

