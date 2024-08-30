## Log

Zig struct representation of the log RPC response.

### Properties

```zig
struct {
  blockHash: ?Hash
  address: Address
  logIndex: ?usize
  data: Hex
  removed: bool
  topics: []const ?Hash
  blockNumber: ?u64
  transactionIndex: ?usize
  transactionHash: ?Hash
  transactionLogIndex: ?usize = null
  blockTimestamp: ?u64 = null
}
```

## Logs

Slice of the struct log

```zig
[]const Log
```

## LogRequest

Its default all null so that when it gets stringified
Logs request struct used by the RPC request methods.
we can use `ignore_null_fields` to omit these fields

### Properties

```zig
struct {
  fromBlock: ?u64 = null
  toBlock: ?u64 = null
  address: ?Address = null
  topics: ?[]const ?Hex = null
  blockHash: ?Hash = null
}
```

## LogTagRequest

Same as `LogRequest` but `fromBlock` and
`toBlock` are tags.

### Properties

```zig
struct {
  fromBlock: ?BalanceBlockTag = null
  toBlock: ?BalanceBlockTag = null
  address: ?Address = null
  topics: ?[]const ?Hex = null
  blockHash: ?Hash = null
}
```

## WatchLogsRequest

Options for `watchLogs` websocket request.

### Properties

```zig
struct {
  address: Address
  topics: ?[]const ?Hex = null
}
```

