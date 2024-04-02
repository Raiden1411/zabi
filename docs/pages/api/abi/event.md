# `AbiEvent` 

Zig representation of the [ABI Event](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

```zig
const zabi = @import("zabi");

const Abi = zabi.abi.Event;

// Internal representation
const Event = struct {
    type: Extract(Abitype, "event"),
    inputs: []const AbiParameter,
    name: []const u8,
    anonymous: ?bool = null,
}
```

This type also includes methods that can be used for formatting/encoding.

## Prepare

This method converts the struct signature into a human readable format that is ready to be hash. This is intended to be used with a `Writer`

This takes in 1 arguments:

- any writer from the std or custom writer.

```zig
const std = @import("std");
const Event = @import("zabi").abi.Event;

const abi_event: Event = .{
  .type = .event, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
//^?
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

This takes in 2 arguments:

- an allocator used to manage the memory allocations
- any writer from the std or custom writer.

**Memory must be freed after calling this method.**

```zig
const std = @import("std");
const Event = @import("zabi").abi.Event;

const abi_event: Event = .{
  .type = .event, 
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

Generates Abi encoded data using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json) by a given set of inputs and the associated values.

**Current we don't support encoding the values. But expect this to change in a future release.**

This takes in 1 arguments:

- an allocator used to manage the memory allocations

**Memory must be freed after calling this method.**

```zig
const std = @import("std");
const Event = @import("zabi").abi.Event;

const abi_event: Event = .{
  .type = .event, 
  .name = "Transfer", 
  .inputs = &.{
      .{ .type = .{ .address = {} }, .name = "from", .indexed = true}, 
      .{ .type = .{ .address = {} }, .name = "to", .indexed = true},
      .{ .type = .{ .uint = 256 }, .name = "tokenId", .indexed = false},
    },
};

const encoded = try abi_event.encode(std.testing.allocator);

// Result
// ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
```

### Returns

- Type: `[]u8` -> The hex encoded event signature.

## Format

Format the event struct signature into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const Event = @import("zabi").abi.Event;

const abi_event: Event = .{
  .type = .event, 
  .name = "Foo", 
  .inputs = &.{
      .{ .type = .{ .bool = {} }, .name = "foo"}, 
      .{ .type = .{ .string = {} }, .name = "bar" } 
    },
};

std.debug.print("{s}", .{abi_event});

// Outputs
// event Foo(bool foo, string bar)
```

### Returns

- Type: `void`
