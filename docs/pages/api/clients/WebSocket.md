## ConnectionErrors

Set of connection errors when establishing a connection.

```zig
error{
    UnsupportedSchema,
    FailedToConnect,
    MissingUrlPath,
    OutOfMemory,
    UnspecifiedHostName,
    InvalidNetworkConfig,
}
```

## InitErrors

Set of possible errors when starting the client.

```zig
ConnectionErrors || Allocator.Error || std.Thread.SpawnError
```

## SocketWriteErrors

Set of possible errors when writting to a socket.

```zig
std.net.Stream.WriteError || std.crypto.tls.Client.StreamInterface.WriteError || Allocator.Error
```

## SendRpcRequestErrors

Set of possible errors when sending a rpc request.

```zig
EthereumZigErrors || SocketWriteErrors || ParseFromValueError || error{ReachedMaxRetryLimit}
```

## BasicRpcRequestErrors

Set of generic errors when sending rpc request.

```zig
SendRpcRequestErrors || error{NoSpaceLeft}
```

## InitOptions

### Properties

```zig
struct {
  /// Allocator to use to create the ChildProcess and other allocations
  allocator: Allocator
  /// The chains config
  network_config: NetworkConfig
  /// Callback function for when the connection is closed.
  onClose: ?*const fn () void = null
  /// Callback function for everytime an event is parsed.
  onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null
  /// Callback function for everytime an error is caught.
  onError: ?*const fn (args: []const u8) anyerror!void = null
}
```

## ServerMessage
This will get run everytime a socket message is found.
All messages are parsed and put into the handlers channel.
All callbacks will only affect this function.

### Signature

```zig
pub fn serverMessage(
    self: *WebSocketHandler,
    message: []u8,
    message_type: ws.MessageTextType,
) (Stack(JsonParsed(Value)).Error || error{ FailedToJsonParseResponse, InvalidTypeMessage, UnexpectedError })!void
```

## Init
Populates the WebSocketHandler pointer.
Starts the connection in a seperate process.

### Signature

```zig
pub fn init(opts: InitOptions) InitErrors!*WebSocketHandler
```

## Deinit
All future interactions will deadlock
If you are using the subscription channel this operation can take time
as it will need to cleanup each node.

### Signature

```zig
pub fn deinit(self: *WebSocketHandler) void
```

## Connect
Connects to a socket client. This is a blocking operation.

### Signature

```zig
pub fn connect(self: *WebSocketHandler) ConnectionErrors!ws.Client
```

## Close
Runs the callback once the handler close method gets called by the ws_client

### Signature

```zig
pub fn close(self: *WebSocketHandler) void
```

## BlobBaseFee
Grabs the current base blob fee.

RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)

### Signature

```zig
pub fn blobBaseFee(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(Gwei)
```

## CreateAccessList
Create an accessList of addresses and storageKeys for an transaction to access

RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)

### Signature

```zig
pub fn createAccessList(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) BasicRpcRequestErrors!RPCResponse(AccessListResult)
```

## EstimateBlobMaxFeePerGas
Estimate the gas used for blobs
Uses `blobBaseFee` and `gasPrice` to calculate this estimation

### Signature

```zig
pub fn estimateBlobMaxFeePerGas(self: *WebSocketHandler) !Gwei
```

## EstimateFeesPerGas
Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
Uses the `baseFeePerGas` included in the block to calculate the gas fees.
Will return an error in case the `baseFeePerGas` is null.

### Signature

```zig
pub fn estimateFeesPerGas(
    self: *WebSocketHandler,
    call_object: EthCall,
    base_fee_per_gas: ?Gwei,
) (BasicRpcRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!EstimateFeeReturn
```

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
The transaction will not be added to the blockchain.
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.

RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

### Signature

```zig
pub fn estimateGas(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) BasicRpcRequestErrors!RPCResponse(Gwei)
```

## EstimateMaxFeePerGasManual
Estimates maxPriorityFeePerGas manually. If the node you are currently using
supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGasManual(
    self: *WebSocketHandler,
    base_fee_per_gas: ?Gwei,
) (BasicRpcRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!Gwei
```

## EstimateMaxFeePerGas
Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGas(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(Gwei)
```

## FeeHistory
Returns historical gas information, allowing you to track trends over time.

RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)

### Signature

```zig
pub fn feeHistory(
    self: *WebSocketHandler,
    blockCount: u64,
    newest_block: BlockNumberRequest,
    reward_percentil: ?[]const f64,
) BasicRpcRequestErrors!RPCResponse(FeeHistory)
```

## GetAccounts
Returns a list of addresses owned by client.

RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)

### Signature

```zig
pub fn getAccounts(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse([]const Address)
```

## GetAddressBalance
Returns the balance of the account of given address.

RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)

### Signature

```zig
pub fn getAddressBalance(self: *WebSocketHandler, opts: BalanceRequest) BasicRpcRequestErrors!RPCResponse(Wei)
```

## GetAddressTransactionCount
Returns the number of transactions sent from an address.

RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)

### Signature

```zig
pub fn getAddressTransactionCount(self: *WebSocketHandler, opts: BalanceRequest) BasicRpcRequestErrors!RPCResponse(u64)
```

## GetBlockByHash
Returns the number of most recent block.

RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHash(
    self: *WebSocketHandler,
    opts: BlockHashRequest,
) (BasicRpcRequestErrors || error{InvalidBlockHash})!RPCResponse(Block)
```

## GetBlockByHashType
Returns information about a block by hash.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHashType(
    self: *WebSocketHandler,
    comptime T: type,
    opts: BlockHashRequest,
) (BasicRpcRequestErrors || error{InvalidBlockHash})!RPCResponse(T)
```

## GetBlockByNumber
Returns information about a block by number.

RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumber(self: *WebSocketHandler, opts: BlockRequest) (BasicRpcRequestErrors || error{InvalidBlockNumber})!RPCResponse(Block)
```

## GetBlockByNumberType
Returns information about a block by number.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumberType(
    self: *WebSocketHandler,
    comptime T: type,
    opts: BlockRequest,
) (BasicRpcRequestErrors || error{InvalidBlockNumber})!RPCResponse(T)
```

## GetBlockNumber
Returns the number of transactions in a block from a block matching the given block number.

RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)

### Signature

```zig
pub fn getBlockNumber(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(u64)
```

## GetBlockTransactionCountByHash
Returns the number of transactions in a block from a block matching the given block hash.

RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)

### Signature

```zig
pub fn getBlockTransactionCountByHash(self: *WebSocketHandler, block_hash: Hash) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetBlockTransactionCountByNumber
Returns the number of transactions in a block from a block matching the given block number.

RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)

### Signature

```zig
pub fn getBlockTransactionCountByNumber(self: *WebSocketHandler, opts: BlockNumberRequest) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetChainId
Returns the chain ID used for signing replay-protected transactions.

RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)

### Signature

```zig
pub fn getChainId(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetClientVersion
Returns the node's client version

RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)

### Signature

```zig
pub fn getClientVersion(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse([]const u8)
```

## GetContractCode
Returns code at a given address.

RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)

### Signature

```zig
pub fn getContractCode(self: *WebSocketHandler, opts: BalanceRequest) BasicRpcRequestErrors!RPCResponse(Hex)
```

## GetCurrentRpcEvent
Get the first event of the rpc channel.

Only call this if you are sure that the channel has messages
because this will block until a message is able to be fetched.

### Signature

```zig
pub fn getCurrentRpcEvent(self: *WebSocketHandler) JsonParsed(Value)
```

## GetCurrentSubscriptionEvent
Get the first event of the subscription channel.

Only call this if you are sure that the channel has messages
because this will block until a message is able to be fetched.

### Signature

```zig
pub fn getCurrentSubscriptionEvent(self: *WebSocketHandler) JsonParsed(Value)
```

## GetFilterOrLogChanges
Polling method for a filter, which returns an array of logs which occurred since last poll or
returns an array of all logs matching filter with given id depending on the selected method.

https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs

### Signature

```zig
pub fn getFilterOrLogChanges(
    self: *WebSocketHandler,
    filter_id: u128,
    method: EthereumRpcMethods,
) (BasicRpcRequestErrors || error{ InvalidFilterId, InvalidRpcMethod })!RPCResponse(Logs)
```

## GetGasPrice
Returns an estimate of the current price per gas in wei.
For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.

RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)

### Signature

```zig
pub fn getGasPrice(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(Gwei)
```

## GetLogs
Returns an array of all logs matching a given filter object.

RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)

### Signature

```zig
pub fn getLogs(
    self: *WebSocketHandler,
    opts: LogRequest,
    tag: ?BalanceBlockTag,
) (BasicRpcRequestErrors || error{InvalidLogRequestParams})!RPCResponse(Logs)
```

## GetLogsSubEvent
Parses the `Value` in the sub-channel as a log event

### Signature

```zig
pub fn getLogsSubEvent(self: *WebSocketHandler) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Log))
```

## GetNewHeadsBlockSubEvent
Parses the `Value` in the sub-channel as a new heads block event

### Signature

```zig
pub fn getNewHeadsBlockSubEvent(self: *WebSocketHandler) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Block))
```

## GetNetworkListenStatus
Returns true if client is actively listening for network connections.

RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)

### Signature

```zig
pub fn getNetworkListenStatus(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(bool)
```

## GetNetworkPeerCount
Returns number of peers currently connected to the client.

RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)

### Signature

```zig
pub fn getNetworkPeerCount(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetNetworkVersionId
Returns the current network id.

RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)

### Signature

```zig
pub fn getNetworkVersionId(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetPendingTransactionsSubEvent
Parses the `Value` in the sub-channel as a pending transaction hash event

### Signature

```zig
pub fn getPendingTransactionsSubEvent(self: *WebSocketHandler) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Hash))
```

## GetProof
Returns the account and storage values, including the Merkle proof, of the specified account

RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)

### Signature

```zig
pub fn getProof(
    self: *WebSocketHandler,
    opts: ProofRequest,
    tag: ?ProofBlockTag,
) (BasicRpcRequestErrors || error{ExpectBlockNumberOrTag})!RPCResponse(ProofResult)
```

## GetProtocolVersion
Returns the current Ethereum protocol version.

RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)

### Signature

```zig
pub fn getProtocolVersion(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(u64)
```

## GetRawTransactionByHash
Returns the raw transaction data as a hexadecimal string for a given transaction hash

RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)

### Signature

```zig
pub fn getRawTransactionByHash(self: *WebSocketHandler, tx_hash: Hash) BasicRpcRequestErrors!RPCResponse(Hex)
```

## GetSha3Hash
Returns the Keccak256 hash of the given message.

RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)

### Signature

```zig
pub fn getSha3Hash(
    self: *WebSocketHandler,
    message: []const u8,
) (BasicRpcRequestErrors || error{ InvalidCharacter, InvalidLength })!RPCResponse(Hash)
```

## GetStorage
Returns the value from a storage position at a given address.

RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)

### Signature

```zig
pub fn getStorage(
    self: *WebSocketHandler,
    address: Address,
    storage_key: Hash,
    opts: BlockNumberRequest,
) BasicRpcRequestErrors!RPCResponse(Hash)
```

## GetSyncStatus
Returns null if the node has finished syncing. Otherwise it will return
the sync progress.

RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)

### Signature

```zig
pub fn getSyncStatus(self: *WebSocketHandler) ?RPCResponse(SyncProgress)
```

## GetTransactionByBlockHashAndIndex
Returns information about a transaction by block hash and transaction index position.

RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndex(
    self: *WebSocketHandler,
    block_hash: Hash,
    index: usize,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByBlockHashAndIndexType
Returns information about a transaction by block hash and transaction index position.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndexType(
    self: *WebSocketHandler,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionByBlockNumberAndIndex
### Signature

```zig
pub fn getTransactionByBlockNumberAndIndex(
    self: *WebSocketHandler,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByBlockNumberAndIndexType
Returns information about a transaction by block number and transaction index position.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)

### Signature

```zig
pub fn getTransactionByBlockNumberAndIndexType(
    self: *WebSocketHandler,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionByHash
Returns the information about a transaction requested by transaction hash.

RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHash(
    self: *WebSocketHandler,
    transaction_hash: Hash,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByHashType
Returns the information about a transaction requested by transaction hash.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHashType(
    self: *WebSocketHandler,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRpcRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionReceipt
Returns the receipt of a transaction by transaction hash.

RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn getTransactionReceipt(
    self: *WebSocketHandler,
    transaction_hash: Hash,
) (BasicRpcRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(TransactionReceipt)
```

## GetTransactionReceiptType
Returns the receipt of a transaction by transaction hash.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn getTransactionReceiptType(
    self: *WebSocketHandler,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRpcRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(T)
```

## GetTxPoolContent
The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.

The result is an object with two fields pending and queued.
Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.
These batches themselves are maps associating nonces with actual transactions.

RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContent(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(TxPoolContent)
```

## GetTxPoolContentFrom
Retrieves the transactions contained within the txpool,
returning pending as well as queued transactions of this address, grouped by nonce

RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContentFrom(self: *WebSocketHandler, from: Address) BasicRpcRequestErrors!RPCResponse([]const PoolTransactionByNonce)
```

## GetTxPoolInspectStatus
The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.
This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.

RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolInspectStatus(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(TxPoolInspect)
```

## GetTxPoolStatus
The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.

RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolStatus(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(TxPoolStatus)
```

## GetUncleByBlockHashAndIndex
Returns information about a uncle of a block by hash and uncle index position.

RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndex(
    self: *WebSocketHandler,
    block_hash: Hash,
    index: usize,
) (BasicRpcRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(Block)
```

## GetUncleByBlockHashAndIndexType
Returns information about a uncle of a block by hash and uncle index position.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndexType(
    self: *WebSocketHandler,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRpcRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(T)
```

## GetUncleByBlockNumberAndIndex
Returns information about a uncle of a block by number and uncle index position.

RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndex(
    self: *WebSocketHandler,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRpcRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(Block)
```

## GetUncleByBlockNumberAndIndexType
Returns information about a uncle of a block by number and uncle index position.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndexType(
    self: *WebSocketHandler,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRpcRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(T)
```

## GetUncleCountByBlockHash
Returns the number of uncles in a block from a block matching the given block hash.

RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)

### Signature

```zig
pub fn getUncleCountByBlockHash(self: *WebSocketHandler, block_hash: Hash) BasicRpcRequestErrors!RPCResponse(usize)
```

## GetUncleCountByBlockNumber
Returns the number of uncles in a block from a block matching the given block number.

RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)

### Signature

```zig
pub fn getUncleCountByBlockNumber(self: *WebSocketHandler, opts: BlockNumberRequest) BasicRpcRequestErrors!RPCResponse(usize)
```

## Multicall3
Runs the selected multicall3 contracts.
This enables to read from multiple contract by a single `eth_call`.
Uses the contracts created [here](https://www.multicall3.com/)

To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)

You will need to decoded each of the `Result`.

**Example:**
```zig
 const supply: Function = .{
      .type = .function,
      .name = "totalSupply",
      .stateMutability = .view,
      .inputs = &.{},
      .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
  };

  const balance: Function = .{
      .type = .function,
      .name = "balanceOf",
      .stateMutability = .view,
      .inputs = &.{.{ .type = .{ .address = {} }, .name = "balanceOf" }},
      .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
  };

  const a: []const MulticallTargets = &.{
      .{ .function = supply, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
      .{ .function = balance, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
  };

  const res = try client.multicall3(a, .{ {}, .{try utils.addressToBytes("0xFded38DF0180039867E54EBdec2012D534862cE3")} }, true);
  defer res.deinit();
```

### Signature

```zig
pub fn multicall3(
    self: *WebSocketHandler,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) !AbiDecoded([]const Result)
```

## NewBlockFilter
Creates a filter in the node, to notify when a new block arrives.
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)

### Signature

```zig
pub fn newBlockFilter(self: *WebSocketHandler) !RPCResponse(u128)
```

## NewLogFilter
Creates a filter object, based on filter options, to notify when the state changes (logs).
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)

### Signature

```zig
pub fn newLogFilter(self: *WebSocketHandler, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128)
```

## NewPendingTransactionFilter
Creates a filter in the node, to notify when new pending transactions arrive.
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)

### Signature

```zig
pub fn newPendingTransactionFilter(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(u128)
```

## ParseSubscriptionEvent
Parses a subscription event `Value` into `T`.
Usefull for events that currently zabi doesn't have custom support.

### Signature

```zig
pub fn parseSubscriptionEvent(self: *WebSocketHandler, comptime T: type) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(T))
```

## ReadLoopOwned
This is a blocking operation.
Best to call this in a seperate thread.

### Signature

```zig
pub fn readLoopOwned(self: *WebSocketHandler) void
```

## SendEthCall
Executes a new message call immediately without creating a transaction on the block chain.
Often used for executing read-only smart contract functions,
for example the balanceOf for an ERC-20 contract.

Call object must be prefilled before hand. Including the data field.
This will just make the request to the network.

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn sendEthCall(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) BasicRpcRequestErrors!RPCResponse(Hex)
```

## SendRawTransaction
Creates new message call transaction or a contract creation for signed transactions.
Transaction must be serialized and signed before hand.

RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

### Signature

```zig
pub fn sendRawTransaction(self: *WebSocketHandler, serialized_tx: Hex) BasicRpcRequestErrors!RPCResponse(Hash)
```

## SendRpcRequest
Writes message to websocket server and parses the reponse from it.
This blocks until it gets the response back from the server.

### Signature

```zig
pub fn sendRpcRequest(self: *WebSocketHandler, comptime T: type, message: []u8) SendRpcRequestErrors!RPCResponse(T)
```

## UninstallFilter
Uninstalls a filter with given id. Should always be called when watch is no longer needed.
Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.

RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)

### Signature

```zig
pub fn uninstallFilter(self: *WebSocketHandler, id: usize) BasicRpcRequestErrors!RPCResponse(bool)
```

## Unsubscribe
Unsubscribe from different Ethereum event types with a regular RPC call
with eth_unsubscribe as the method and the subscriptionId as the first parameter.

RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)

### Signature

```zig
pub fn unsubscribe(self: *WebSocketHandler, sub_id: u128) BasicRpcRequestErrors!RPCResponse(bool)
```

## WatchNewBlocks
Emits new blocks that are added to the blockchain.

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)

### Signature

```zig
pub fn watchNewBlocks(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(u128)
```

## WatchLogs
Emits logs attached to a new block that match certain topic filters and address.

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)

### Signature

```zig
pub fn watchLogs(self: *WebSocketHandler, opts: WatchLogsRequest) BasicRpcRequestErrors!RPCResponse(u128)
```

## WatchTransactions
Emits transaction hashes that are sent to the network and marked as "pending".

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)

### Signature

```zig
pub fn watchTransactions(self: *WebSocketHandler) BasicRpcRequestErrors!RPCResponse(u128)
```

## WatchWebsocketEvent
Creates a new subscription for desired events. Sends data as soon as it occurs

This expects the method to be a valid websocket subscription method.
Since we have no way of knowing all possible or custom RPC methods that nodes can provide.

Returns the subscription Id.

### Signature

```zig
pub fn watchWebsocketEvent(self: *WebSocketHandler, method: []const u8) BasicRpcRequestErrors!RPCResponse(u128)
```

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceipt(self: *WebSocketHandler, tx_hash: Hash, confirmations: u8) (BasicRpcRequestErrors || ParseFromValueError || error{
    InvalidBlockNumber,
    TransactionReceiptNotFound,
    TransactionNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
})!RPCResponse(TransactionReceipt)
```

## WaitForTransactionReceiptType
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

Use this in case our block type doesnt support the values of the response from the rpc server
and you know the shape that the data will be like.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceiptType(self: *WebSocketHandler, comptime T: type, tx_hash: Hash, confirmations: u8) (BasicRpcRequestErrors || ParseFromValueError || error{
    InvalidBlockNumber,
    TransactionReceiptNotFound,
    TransactionNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
})!RPCResponse(T)
```

## WriteSocketMessage
Write messages to the websocket server.

### Signature

```zig
pub fn writeSocketMessage(self: *WebSocketHandler, data: []u8) SocketWriteErrors!void
```

