## SyncStatus

Result when calling `eth_syncing` if a node hasn't finished syncing

### Properties

```zig
startingBlock: u64
currentBlock: u64
highestBlock: u64
syncedAccounts: u64
syncedAccountsBytes: u64
syncedBytecodes: u64
syncedBytecodesBytes: u64
syncedStorage: u64
syncedStorageBytes: u64
healedTrienodes: u64
healedTrienodeBytes: u64
healedBytecodes: u64
healedBytecodesBytes: u64
healingTrienodes: u64
healingBytecode: u64
txIndexFinishedBlocks: u64
txIndexRemainingBlocks: u64
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

## JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

## JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

