# Encode Abi Parameters

## Definition
Generates Abi encoded data using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json) by a given set of of inputs or outputs and the associated values.

Zabi supports encoding `AbiParameters` that are either comptime know or runtime know. It is advised that if you know the specification you are working with is comptime know to use `encodeAbiParametersComptime`.

## Usage

`encodeAbiParameters` takes in 3 parameters.

- a allocator used to perform any sort of memory allocations.
- a set of Abi Parameters.
- a tuple of values that the type corresponds to the given set of parameters.

All memory will be managed by a `ArenaAllocator`. You must call `deinit()` after this call.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_parameters: []const AbiParameter = &.{ .{.type = .{.string = {} }, .name = "foo"} };

const encoded = try encoder.encodeAbiParameters(std.testing.allocator, abi_parameters, .{"Hello World"})
defer encoded.deinit();

// Result
// 00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000
```

This same example of usage could be used with `encodeAbiParametersComptime` because here the Abi Parameter is comptime know.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_parameters: []const AbiParameter = &.{ .{.type = .{.string = {} }, .name = "foo"} };

const encoded = try encoder.encodeAbiParametersComptime(std.testing.allocator, abi_parameters, .{"Hello World"})
defer encoded.deinit();

// Result
// 00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000
```

The main benifit of using this is that we can infer which is the expected type of the `values` to encode. This leads to better help from the compiler on what are the expected types instead of having it solely rely on type reflection

You could also use the `encode` method that the Abi Parameter type has.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_parameters: AbiParameter =  .{.type = .{.string = {} }, .name = "foo"};

const encoded = try abi_parameters.encode(std.testing.allocator, .{"Hello World"})
defer encoded.deinit();

// Result
// 00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000
```

In this example you will not need to pass in the `params` arguments and it will use `self` for this.

## Returns

Type: `AbiEncoded`

A struct with the following fields.

- arena: `*ArenaAllocator`
- data: `[]u8`. This is **not** hex encoded. You must do this after.

