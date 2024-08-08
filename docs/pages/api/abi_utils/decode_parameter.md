# `decodeAbiParameter`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 4 arguments:

- a `type` that is used as the expected return type of this call.
- an allocator used to manage the memory allocations
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const AbiParameter = @import("zabi").param.AbiParameter;

const ReturnType = std.meta.Tuple(&[_]type{bool});

const encoded = "0000000000000000000000000000000000000000000000000000000000000001"

const decoded = try decoder.decodeAbiParameters(ReturnType, std.testing.allocator, ReturnType, &.{abi_parameter}, encoded, .{})
defer decoded.deinit();

// Result
// .{true}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded error.

- Type: `AbiDecoded(T)`

