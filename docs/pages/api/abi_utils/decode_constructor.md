# `decodeAbiConstructorRuntime`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 5 arguments:

- an allocator used to manage the memory allocations
- a `type` that is used as the expected return type of this call.
- the `AbiConstructor` struct signature.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const Constructor = @import("zabi").abi.Constructor;

const abi_constructor: Constructor = .{
  .type = .constructor, 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
  .stateMutability = .nonpayable,
};

const ReturnType = std.meta.Tuple(&[_]type{bool , []const u8});
const encoded = "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000"

const decoded = try decoder.decodeAbiConstructorRuntime(std.testing.allocator, ReturnType, abi_constructor, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded constructor parameters.

- Type: `AbiSignatureDecodeRuntime(T)`

# `decodeAbiConstructor`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
This expects that the constructor struct is comptime know. With this we don't need to know the expected return type since zabi can infer the return type from the struct signature.

This takes in 4 arguments:

- an allocator used to manage the memory allocations
- the `AbiConstructor` struct signature.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const Constructor = @import("zabi").abi.Constructor;

const abi_constructor: Constructor = .{
  .type = .constructor, 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
  .stateMutability = .nonpayable,
};

const encoded = "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000"

const decoded = try decoder.decodeAbiConstructor(std.testing.allocator, abi_constructor, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

- Type: `AbiSignatureDecode(constructor.inputs)`
