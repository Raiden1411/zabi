# `decodeAbiErrorRuntime`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 5 arguments:

- an allocator used to manage the memory allocations
- a `type` that is used as the expected return type of this call.
- the `AbiError` struct signature.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

const ReturnType = std.meta.Tuple(&[_]type{bool , []const u8});
const encoded = "65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000"

const decoded = try decoder.decodeAbiErrorRuntime(std.testing.allocator, ReturnType, abi_error, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded error.

- Type: `AbiSignatureDecodeRuntime(T)`


# `decodeAbiError`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
This expects that the function struct is comptime know. With this we don't need to know the expected return type since zabi can infer the return type from the struct signature.

This takes in 4 arguments:

- an allocator used to manage the memory allocations
- the `AbiError` struct signature.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

const encoded = "65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000"

const decoded = try decoder.decodeAbiError(std.testing.allocator, abi_error, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

- Type: `AbiSignatureDecode(err.inputs)`
