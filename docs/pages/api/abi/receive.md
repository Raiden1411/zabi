# `AbiReceive` 

Zig representation of the [ABI Receive](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

```zig
const zabi = @import("zabi");

const Receive = zabi.abi.Receive;

// Internal representation
const Receive = struct {
    type: Extract(Abitype, "fallback"),
    stateMutability: Extract(StateMutability, "payable")
}
```

## Format

Format the receive struct signature into a human readable format.
This is a custom format method that will override all call from the `std` to format methods

```zig
const std = @import("std");
const Receive = @import("zabi").abi.Receive;

const abi_receive: Receive = .{
  .type = .receive, 
  .stateMutability = .payable,
};

std.debug.print("{s}", .{abi_receive});

// Outputs
// receive() external payable
```

### Returns

- Type: `void`
