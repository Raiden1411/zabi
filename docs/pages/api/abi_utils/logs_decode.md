# `decodeLogs`

## Definition
Decoded the generated Abi encoded data into decoded native types using the [contract ABI specification](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
This is only for abi `Event` types that are indexed. Meaning that essentially it decoded log topics.

This takes in 3 arguments:

- a `type` that is used as the expected return type of this call.
- the abi encoded hex string.
- the options used for decoding (Checkout the options here: [LogDecoderOptions](/api/abi_utils/types#logdecoderoptions))

```zig
const encoder_logs = @import("zabi").encoder_logs;
const human = @import("zabi").humam;
const logs_decoder = @import("zabi").logs_decoder;
const std = @import("std");

const event = try human.parseHumanReadable(AbiEvent, testing.allocator, "event Foo(bytes5 indexed a)");
defer event.deinit();

const encoded = try encoder_logs.encodeLogs(testing.allocator, event.value, .{"hello"});
defer testing.allocator.free(encoded);

/// For solidity [1..32] bytes you must decode them as little endian. More details are on `LogDecoderOptions`.
const decoded = try decodeLogs(struct { Hash, [5]u8 }, encoded, .{ .bytes_endian = .little });
```

### Returns

The return value is the provided type.

- Type: `T`

