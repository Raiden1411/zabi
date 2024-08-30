## EncodeLogTopicsComptime
Encode event log topics were the abi event is comptime know.

`values` is expected to be a tuple of the values to encode.
Array and tuples are encoded as the hash representing their values.

Example:

const event = .{
    .type = .event,
    .inputs = &.{},
    .name = "Transfer"
}

const encoded = encodeLogTopicsComptime(testing.allocator, event, .{});

Result: &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}

### Signature

```zig
pub fn encodeLogTopicsComptime(allocator: Allocator, comptime event: AbiEvent, values: AbiEventParametersDataToPrimative(event.inputs)) ![]const ?Hash
```

## EncodeLogTopics
Encode event log topics

`values` is expected to be a tuple of the values to encode.
Array and tuples are encoded as the hash representing their values.

Example:

const event = .{
    .type = .event,
    .inputs = &.{},
    .name = "Transfer"
}

const encoded = encodeLogTopics(testing.allocator, event, .{});

Result: &.{try utils.hashToBytes("0x406dade31f7ae4b5dbc276258c28dde5ae6d5c2773c5745802c493a2360e55e0")}

### Signature

```zig
pub fn encodeLogTopics(allocator: Allocator, event: AbiEvent, values: anytype) ![]const ?Hash
```

