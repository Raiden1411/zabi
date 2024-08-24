## EncodeErrors

```zig
std.mem.Allocator.Error || error{ InvalidIntType, Overflow, BufferExceedsMaxSize, InvalidBits, InvalidLength, NoSpaceLeft, InvalidCharacter, InvalidParamType }
```

## PreEncodedParam

### Properties

```zig
struct {
  dynamic: bool
  encoded: []u8
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), alloc: std.mem.Allocator) void
```

## AbiEncoded

### Properties

```zig
struct {
  arena: *ArenaAllocator
  data: []u8
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This()) void
```

## EncodeAbiConstructorComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiConstructorComptime(allocator: Allocator, comptime constructor: Constructor, values: AbiParametersToPrimative(constructor.inputs)) EncodeErrors!AbiEncoded
```

## EncodeAbiErrorComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiErrorComptime(allocator: Allocator, comptime err: Error, values: AbiParametersToPrimative(err.inputs)) EncodeErrors![]u8
```

## EncodeAbiFunctionComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiFunctionComptime(allocator: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.inputs)) EncodeErrors![]u8
```

## EncodeAbiFunctionOutputsComptime
Encode the struct signature based on the values provided.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiFunctionOutputsComptime(allocator: Allocator, comptime function: Function, values: AbiParametersToPrimative(function.outputs)) EncodeErrors![]u8
```

## EncodeAbiParametersComptime
Main function that will be used to encode abi paramters.\
This will allocate and a ArenaAllocator will be used to manage the memory.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiParametersComptime(alloc: Allocator, comptime parameters: []const AbiParameter, values: AbiParametersToPrimative(parameters)) EncodeErrors!AbiEncoded
```

## EncodeAbiParametersLeakyComptime
Subset function used for encoding. Its highly recommend to use an ArenaAllocator
or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
and with those all of the memory can be freed at once.\
Caller owns the memory.

### Signature

```zig
pub fn encodeAbiParametersLeakyComptime(alloc: Allocator, comptime params: []const AbiParameter, values: AbiParametersToPrimative(params)) EncodeErrors![]u8
```

## EncodeAbiParameters
Main function that will be used to encode abi paramters.\
This will allocate and a ArenaAllocator will be used to manage the memory.\
Caller owns the memory.\
If the parameters are comptime know consider using `encodeAbiParametersComptime`
This will provided type safe values to be passed into the function.\
However runtime reflection will happen to best determine what values should be used based
on the parameters passed in.

### Signature

```zig
pub fn encodeAbiParameters(alloc: Allocator, parameters: []const AbiParameter, values: anytype) EncodeErrors!AbiEncoded
```

## EncodeAbiParametersLeaky
Subset function used for encoding. Its highly recommend to use an ArenaAllocator
or a FixedBufferAllocator to manage memory since allocations will not be freed when done,
and with those all of the memory can be freed at once.\
Caller owns the memory.\
If the parameters are comptime know consider using `encodeAbiParametersComptimeLeaky`
This will provided type safe values to be passed into the function.\
However runtime reflection will happen to best determine what values should be used based
on the parameters passed in.

### Signature

```zig
pub fn encodeAbiParametersLeaky(alloc: Allocator, params: []const AbiParameter, values: anytype) EncodeErrors![]u8
```

## EncodePacked
Encode values based on solidity's `encodePacked`.\
Solidity types are infered from zig ones since it closely follows them.\
Caller owns the memory and it must free them.

### Signature

```zig
pub fn encodePacked(allocator: Allocator, values: anytype) ![]u8
```

