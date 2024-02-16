# Abi Parameters


## `AbiParameter` 

Zig representation of the inputs and outputs for Abi functions, errors, and constructors.

```zig
const zabi = @import("zabi");

const AbiParameter = zabi.param.AbiParameter;

// Internal representation
const AbiParameter = struct {
    name: []const u8,
    type: ParamType,
    internalType: ?[]const u8 = null,
    components: ?[]const AbiParameter = null,
}
```

## `AbiEventParameter` 

Zig representation of the inputs for Abi Events.

```zig
const zabi = @import("zabi");

const AbiParameter = zabi.param.AbiParameter;

// Internal representation
const AbiParameter = struct {
    name: []const u8,
    type: ParamType,
    indexed: bool = false,
    internalType: ?[]const u8 = null,
    components: ?[]const AbiParameter = null,
}
```

Bellow are the shared methods that these structs have.

## Prepare

This method converts the struct signature into a human readable format that is ready to be hashed. This is intended to be used with a `Writer`

This takes in 1 argument:

- any writer from `std` or any custom writer.

```zig
const std = @import("std");
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

const writer = std.io.getStdOut().writer();

try self.prepare(&writer); 

// Result
// Foo(bool foo, string bar)
```

### Returns

- Type: `void`

## Encode Inputs

Generates Abi encoded data using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json) by a given set of of inputs and the associated values.

This takes in 2 arguments:

- a allocator used to manage the memory allocations
- the values that will be encoded.

**Memory must be freed after calling this method.**

```zig
const std = @import("std");
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

const encoded = try abi_parameter.encode(std.testing.allocator, .{true})

// Result
// 0000000000000000000000000000000000000000000000000000000000000001
```

### Returns

- Type: `[]u8` -> The hex encoded parameter.

## Decode Inputs

Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 4 arguments:

- a allocator used to manage the memory allocations
- a `type` that is used as the expected return type of this call.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

const ReturnType = std.meta.Tuple(&[_]type{bool});

const encoded = "0000000000000000000000000000000000000000000000000000000000000001"

const decoded = try abi_parameter.decode(std.testing.allocator, ReturnType, encoded, .{})
defer decoded.deinit();

// Result
// .{true}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded error.

- Type: `AbiDecodeRuntime(T)`

## Format

Format the error struct signature into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

std.debug.print("{s}", .{abi_parameter});

// Outputs
// bool foo
```

## ParamType

Zig representation of solidity types

```zig
const zabi = @import("zabi");

const AbiParameter = zabi.param_type.ParamType;

// Internal representation
const FixedArray = struct {
    child: *const ParamType,
    size: usize,
};

const ParamType = union(enum) {
    address,
    string,
    bool,
    bytes,
    tuple,
    uint: usize,
    int: usize,
    fixedBytes: usize,
    @"enum": usize,
    fixedArray: FixedArray,
    dynamicArray: *const ParamType,
}
```

These are compatible with json parsing. And there is also some helper methods that can convert from strings to the ParamType representation.

In the case of dynamic arrays or fixed size arrays memory will be allocated and so if you aren't using something like a memory arena you will need to use the `freeArrayParamType` method to destroy all allocated pointers.

### String to ParamType

```zig
try expectEqualParamType(ParamType{ .string = {} }, try ParamType.typeToUnion("string", testing.allocator));
try expectEqualParamType(ParamType{ .address = {} }, try ParamType.typeToUnion("address", testing.allocator));
try expectEqualParamType(ParamType{ .int = 256 }, try ParamType.typeToUnion("int", testing.allocator));
try expectEqualParamType(ParamType{ .uint = 256 }, try ParamType.typeToUnion("uint", testing.allocator));
try expectEqualParamType(ParamType{ .bytes = {} }, try ParamType.typeToUnion("bytes", testing.allocator));
try expectEqualParamType(ParamType{ .bool = {} }, try ParamType.typeToUnion("bool", testing.allocator));
try expectEqualParamType(ParamType{ .tuple = {} }, try ParamType.typeToUnion("tuple", testing.allocator));
try expectEqualParamType(ParamType{ .fixedBytes = 32 }, try ParamType.typeToUnion("bytes32", testing.allocator));

const dynamic = try ParamType.typeToUnion("int[]", testing.allocator);
defer dynamic.freeArrayParamType(testing.allocator);
try expectEqualParamType(ParamType{ .dynamicArray = &.{ .int = 256 } }, dynamic);

const fixed = try ParamType.typeToUnion("int[5]", testing.allocator);
defer fixed.freeArrayParamType(testing.allocator);
try expectEqualParamType(ParamType{ .fixedArray = FixedArray{ .child = &.{ .int = 256 }, .size = 5 } }, fixed);
```
