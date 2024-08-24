## Hex

## Gwei

## Wei

## Hash

## Address

## Subscriptions

```zig
enum {
    newHeads,
    logs,
    newPendingTransactions,
}
```

## EthereumRpcMethods

Set of public rpc actions.

```zig
enum {
    web3_clientVersion,
    web3_sha3,
    net_version,
    net_listening,
    net_peerCount,
    eth_chainId,
    eth_gasPrice,
    eth_accounts,
    eth_getBalance,
    eth_getBlockByNumber,
    eth_getBlockByHash,
    eth_blockNumber,
    eth_getTransactionCount,
    eth_getBlockTransactionCountByHash,
    eth_getBlockTransactionCountByNumber,
    eth_getUncleCountByBlockHash,
    eth_getUncleCountByBlockNumber,
    eth_getCode,
    eth_getTransactionByHash,
    eth_getTransactionByBlockHashAndIndex,
    eth_getTransactionByBlockNumberAndIndex,
    eth_getTransactionReceipt,
    eth_getUncleByBlockHashAndIndex,
    eth_getUncleByBlockNumberAndIndex,
    eth_newFilter,
    eth_newBlockFilter,
    eth_newPendingTransactionFilter,
    eth_uninstallFilter,
    eth_getFilterChanges,
    eth_getFilterLogs,
    eth_getLogs,
    eth_sign,
    eth_signTransaction,
    eth_sendTransaction,
    eth_sendRawTransaction,
    eth_call,
    eth_estimateGas,
    eth_maxPriorityFeePerGas,
    eth_subscribe,
    eth_unsubscribe,
    eth_signTypedData_v4,
    eth_blobBaseFee,
    eth_createAccessList,
    eth_feeHistory,
    eth_getStorageAt,
    eth_getProof,
    eth_protocolVersion,
    eth_syncing,
    eth_getRawTransactionByHash,
    txpool_content,
    txpool_contentFrom,
    txpool_inspect,
    txpool_status,
}
```

## PublicChains

Enum of know chains.\
More will be added in the future.

## RPCResponse
Wrapper around std.json.Parsed(T). Response for any of the RPC clients

### Signature

```zig
pub fn RPCResponse(comptime T: type) type
```

## Deinit
### Signature

```zig
pub fn deinit(self: @This()) void
```

## FromJson
### Signature

```zig
pub fn fromJson(arena: *ArenaAllocator, value: T) @This()
```

## EthereumRequest
Zig struct representation of a RPC Request

### Signature

```zig
pub fn EthereumRequest(comptime T: type) type
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

## EthereumResponse
### Signature

```zig
pub fn EthereumResponse(comptime T: type) type
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
pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void
```

## EthereumRpcResponse
Zig struct representation of a RPC Response

### Signature

```zig
pub fn EthereumRpcResponse(comptime T: type) type
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

## EthereumSubscribeResponse
Zig struct representation of a RPC subscribe response

### Signature

```zig
pub fn EthereumSubscribeResponse(comptime T: type) type
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

## ErrorResponse

Zig struct representation of a RPC error message

### Properties

```zig
code: EthereumErrorCodes
message: []const u8
data: ?[]const u8 = null
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

## ContractErrorResponse

Zig struct representation of a contract error response

### Properties

```zig
code: EthereumErrorCodes
message: []const u8
data: []const u8
```

## EthereumErrorCodes

Ethereum RPC error codes.\
https://eips.ethereum.org/EIPS/eip-1474#error-codes

## EthereumZigErrors

RPC errors in zig format

## EthereumErrorResponse

Zig struct representation of a RPC error response

### Properties

```zig
jsonrpc: []const u8 = "2.0"
id: ?usize = null
@"error": ErrorResponse
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

