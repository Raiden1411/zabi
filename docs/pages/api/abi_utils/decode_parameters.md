# `decodeAbiParametersRuntime`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 5 arguments:

- a allocator used to manage the memory allocations
- a `type` that is used as the expected return type of this call.
- a slice of `AbiParameter` struct signatures.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

const ReturnType = std.meta.Tuple(&[_]type{bool});

const encoded = "0000000000000000000000000000000000000000000000000000000000000001"

const decoded = try decoder.decodeAbiParametersRuntime(std.testing.allocator, ReturnType, &.{abi_parameter}, encoded, .{})
defer decoded.deinit();

// Result
// .{true}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded error.

- Type: `AbiDecodeRuntime(T)`

# `decodeAbiParameters`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
This expects that the parameters struct is comptime know. With this we don't need to know the expected return type since zabi can infer the return type from the struct signature.

This takes in 4 arguments:

- a allocator used to manage the memory allocations
- a slice of `AbiParameter` struct signatures.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const AbiParameter = @import("zabi").param.AbiParameter;

const abi_parameter: AbiParameter = .{ .type = .{ .bool = {} }, .name = "foo"};

const encoded = "0000000000000000000000000000000000000000000000000000000000000001"

const decoded = try decoder.decodeAbiParametersRuntime(std.testing.allocator, &.{abi_parameter}, encoded, .{})
defer decoded.deinit();

// Result
// .{true}
```

### Returns

- Type: `AbiDecode(params)`
