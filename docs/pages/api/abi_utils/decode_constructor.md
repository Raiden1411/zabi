# `decodeAbiConstructor`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

This takes in 5 arguments:

- a `type` that is used as the expected return type of this call.
- an allocator used to manage the memory allocations
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [DecodeOptions](/api/abi_utils/types#decodedoptions))

**You must call `deinit()` after to free any allocated memory.**

```zig
const std = @import("std");
const decoder = @import("zabi").decoder;
const Constructor = @import("zabi").abi.Constructor;

const ReturnType = std.meta.Tuple(&[_]type{bool , []const u8});
const encoded = "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000"

const decoded = try decoder.decodeAbiConstructor(ReturnType, std.testing.allocator, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded constructor parameters.

- Type: `AbiDecoded(T)`

