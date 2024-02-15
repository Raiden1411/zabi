# Encode Abi Error

Generates Abi encoded data using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
 by a given set of of inputs and the associated values.

Zabi supports encoding `AbiError` that are either comptime know or runtime know. It is advised that if you know the specification you are working with is comptime know to use `encodeAbiErrorComptime`.

## Usage

`encodeAbiError` takes in 3 parameters.

- a allocator used to perform any sort of memory allocations.
- a ABI error specification.
- a tuple of values that the type corresponds to the given set of parameters.

All memory will be managed by a `ArenaAllocator`. You must free the memory after this call.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_error: Error = .{.type = .@"error", .name = "Foo", .inputs = &.{.{.type = .{ .bool = {} }, .name = "foo"}, .{ .type = .{ .string = {} }, .name = "bar" } } };

const encoded = try encoder.encodeAbiError(std.testing.allocator, abi_parameters, .{true, "fizzbuzz"})
defer std.testing.allocator.free(encoded);

// Result
// 65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000
```

This same example of usage could be used with `encodeAbiErrorComptime` because here the Abi Parameter is comptime know.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_error: Error = .{.type = .@"error", .name = "Foo", .inputs = &.{.{.type = .{ .bool = {} }, .name = "foo"}, .{ .type = .{ .string = {} }, .name = "bar" } } };

const encoded = try encoder.encodeAbiErrorComptime(std.testing.allocator, abi_parameters, .{true, "fizzbuzz"})
defer std.testing.allocator.free(encoded);

// Result
// 65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000
```

The main benifit of using this is that we can infer which is the expected type of the `values` to encode. This leads to better help from the compiler on what are the expected types instead of having it solely rely on type reflection

You could also use the `encode` method that the Abi Parameter type has.

```zig
const std = @import("std");
const encoder = @import("zabi").encoder;
const abi_error: Error = .{.type = .@"error", .name = "Foo", .inputs = &.{.{.type = .{ .bool = {} }, .name = "foo"}, .{ .type = .{ .string = {} }, .name = "bar" } } };

const encoded = try abi_error.encode(std.testing.allocator, .{true, "fizzbuzz"})

// Result
// 65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000
```

In this example you will not need to pass in the `params` arguments and it will use `self` for this.

## Returns

Type: `[]u8`

The hex encoded string of the encoded abi function.
