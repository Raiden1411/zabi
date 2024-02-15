# `AbiFallback` 

Zig representation of the [ABI Fallback](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

```zig
const zabi = @import("zabi");

const Fallback = zabi.abi.Fallback;

// Internal representation
const Fallback = struct {
    type: Extract(Abitype, "fallback"),
    stateMutability: Extract(StateMutability, "payable,nonpayable")
}
```

## Format

Format the fallback struct signature into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const Fallback = @import("zabi").abi.Fallback;

const abi_fallback: Fallback = .{
  .type = .fallback, 
  .stateMutability = .nonpayable,
};

std.debug.print("{s}", .{abi_fallback});

// Outputs
// fallback()
```

### Returns

- Type: `void`
