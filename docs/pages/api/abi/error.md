# `AbiError` 

Zig representation of the [ABI Error](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

```zig
const zabi = @import("zabi");

const Abi = zabi.abi.Error;

// Internal representation
const Error = struct {
    type: Extract(Abitype, "error"),
    inputs: []const AbiParameter,
    name: []const u8,
}
```

This type also includes methods that can be used for formating, encoding and decoding.

## Prepare

This method converts the struct signature into a human readable format that is ready to be hashed. This is intended to be used with a `Writer`

This takes in 1 argument:

- any writer from `std` or any custom writer.

```zig
const std = @import("std");
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

const writer = std.io.getStdOut().writer();

try self.prepare(&writer);

// Result
// Foo(bool foo, string bar)
```

### Returns

- Type: `void`

## AllocPrepare

Same exact method the difference is that it takes an allocator and returns the encoded string.

This takes in 1 argument:

- any writer from `std` or any custom writer.
- a allocator to manage all memory allocations.

**Memory must be freed after calling this method.**

```zig
const std = @import("std");
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

const writer = std.io.getStdOut().writer();

try self.allocPrepare(std.testing.allocator, &writer);

// Result
// Foo(bool foo, string bar)
```

### Returns

- Type: `[]u8`

## Encode Inputs

Generates Abi encoded data using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json) by a given set of of inputs and the associated values.

This takes in 2 arguments:

- a allocator used to manage the memory allocations
- the values that will be encoded.

**Memory must be freed after calling this method.**

```zig
const std = @import("std");
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

const encoded = try abi_error.encode(std.testing.allocator, .{true, "fizzbuzz"})

// Result
// 65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000
```

### Returns

- Type: `[]u8` -> The hex encoded error.

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

const decoded = try abi_error.decode(std.testing.allocator, ReturnType, encoded, .{})
defer decoded.deinit();

// Result
// .{true, "fizzbuzz"}
```

### Returns

The return value is expected to be a tuple of types used for encoding. Compilation will fail or runtime errors will happen if the incorrect type is passed to the decoded error.

- Type: `AbiSignatureDecodeRuntime(T)`

## Format

Format the error struct signature into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const Error = @import("zabi").abi.Error;

const abi_error: Error = .{
  .type = .error, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

std.debug.print("{s}", .{abi_error});

// Outputs
// error Foo(bool foo, string bar)
```

### Returns

- Type: `void`
