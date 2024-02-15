# `AbiItem`

Union of all possible member of the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

```zig
const zabi = @import("zabi");

const AbiItem = zabi.abi.AbiItem;

// Internal representation
const AbiItem = union(enum) {
    abiFunction: Function,
    abiEvent: Event,
    abiError: Error,
    abiConstructor: Constructor,
    abiFallback: Fallback,
    abiReceive: Receive,
}
```

## Format

Format any of the abi struct signatures into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const AbiItem = @import("zabi").abi.AbiItem;

const abi_item: AbiItem = .{ .abiConstructor = .{
    .type = .constructor, 
    .inputs = &.{
        .{ .type = .{ .bool = {} }, .name = "foo"}, 
        .{ .type = .{ .string = {} }, .name = "bar" } 
      },
    .stateMutability = .nonpayable,
  }
};

std.debug.print("{s}", .{abi_item});

// Outputs
// constructor(bool foo, string bar)
```

# `Abi`

This is a const slice of `AbiItem`. All of the above applies
