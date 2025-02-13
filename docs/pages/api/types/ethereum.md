## Hex

Ethereum hex string types in zabi.

```zig
[]u8
```

## Gwei

Ethereum gwei type in zabi.

```zig
u64
```

## Wei

Ethereum wei value in zabi.

```zig
u256
```

## Hash

Ethereum hash type in zabi.

```zig
[32]u8
```

## Address

Ethereum address type in zabi.

```zig
[20]u8
```

## Subscriptions

RPC subscription calls.

### Properties

```zig
enum {
  newHeads
  logs
  newPendingTransactions
}
```

## EthereumRpcMethods

Set of public rpc actions.

### Properties

```zig
enum {
  web3_clientVersion
  web3_sha3
  net_version
  net_listening
  net_peerCount
  eth_chainId
  eth_gasPrice
  eth_accounts
  eth_getBalance
  eth_getBlockByNumber
  eth_getBlockByHash
  eth_blockNumber
  eth_getTransactionCount
  eth_getBlockTransactionCountByHash
  eth_getBlockTransactionCountByNumber
  eth_getUncleCountByBlockHash
  eth_getUncleCountByBlockNumber
  eth_getCode
  eth_getTransactionByHash
  eth_getTransactionByBlockHashAndIndex
  eth_getTransactionByBlockNumberAndIndex
  eth_getTransactionReceipt
  eth_getUncleByBlockHashAndIndex
  eth_getUncleByBlockNumberAndIndex
  eth_newFilter
  eth_newBlockFilter
  eth_newPendingTransactionFilter
  eth_uninstallFilter
  eth_getFilterChanges
  eth_getFilterLogs
  eth_getLogs
  eth_sign
  eth_signTransaction
  eth_sendTransaction
  eth_sendRawTransaction
  eth_call
  eth_estimateGas
  eth_maxPriorityFeePerGas
  eth_subscribe
  eth_unsubscribe
  eth_signTypedData_v4
  eth_blobBaseFee
  eth_createAccessList
  eth_feeHistory
  eth_getStorageAt
  eth_getProof
  eth_protocolVersion
  eth_syncing
  eth_getRawTransactionByHash
  txpool_content
  txpool_contentFrom
  txpool_inspect
  txpool_status
}
```

## PublicChains

Enum of know chains.
More will be added in the future.

### Properties

```zig
enum {
  ethereum = 1
  goerli = 5
  op_mainnet = 10
  cronos = 25
  bnb = 56
  ethereum_classic = 61
  op_kovan = 69
  gnosis = 100
  polygon = 137
  fantom = 250
  boba = 288
  op_goerli = 420
  base = 8543
  anvil = 31337
  arbitrum = 42161
  arbitrum_nova = 42170
  celo = 42220
  avalanche = 43114
  zora = 7777777
  sepolia = 11155111
  op_sepolia = 11155420
}
```

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
RPC response from an ethereum node. Can be either a success or error response.

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
struct {
  code: EthereumErrorCodes
  message: []const u8
  data: ?[]const u8 = null
}
```

## ContractErrorResponse

Zig struct representation of a contract error response

### Properties

```zig
struct {
  code: EthereumErrorCodes
  message: []const u8
  data: []const u8
}
```

## EthereumErrorCodes

Ethereum RPC error codes.
https://eips.ethereum.org/EIPS/eip-1474#error-codes

### Properties

```zig
enum {
  ContractErrorCode = 3
  TooManyRequests = 429
  UserRejectedRequest = 4001
  Unauthorized = 4100
  UnsupportedMethod = 4200
  Disconnected = 4900
  ChainDisconnected = 4901
  InvalidInput = -32000
  ResourceNotFound = -32001
  ResourceUnavailable = -32002
  TransactionRejected = -32003
  MethodNotSupported = -32004
  LimitExceeded = -32005
  RpcVersionNotSupported = -32006
  InvalidRequest = -32600
  MethodNotFound = -32601
  InvalidParams = -32602
  InternalError = -32603
  ParseError = -32700
  _
}
```

## EthereumZigErrors

RPC errors in zig format

```zig
error{
    EvmFailedToExecute,
    TooManyRequests,
    InvalidInput,
    ResourceNotFound,
    ResourceUnavailable,
    TransactionRejected,
    MethodNotSupported,
    LimitExceeded,
    RpcVersionNotSupported,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    ParseError,
    UnexpectedRpcErrorCode,
    UserRejectedRequest,
    Unauthorized,
    UnsupportedMethod,
    Disconnected,
    ChainDisconnected,
}
```

## EthereumErrorResponse

Zig struct representation of a RPC error response

### Properties

```zig
struct {
  jsonrpc: []const u8 = "2.0"
  id: ?usize = null
  @"error": ErrorResponse
}
```

