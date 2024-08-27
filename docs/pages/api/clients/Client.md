## HttpClientError

```zig
error{
    TransactionNotFound,
    FailedToGetReceipt,
    EvmFailedToExecute,
    InvalidFilterId,
    InvalidLogRequestParams,
    TransactionReceiptNotFound,
    InvalidHash,
    UnexpectedErrorFound,
    UnableToFetchFeeInfoFromBlock,
    UnexpectedTooManyRequestError,
    InvalidInput,
    InvalidParams,
    InvalidRequest,
    InvalidAddress,
    InvalidBlockHash,
    InvalidBlockHashOrIndex,
    InvalidBlockNumberOrIndex,
    TooManyRequests,
    MethodNotFound,
    MethodNotSupported,
    RpcVersionNotSupported,
    LimitExceeded,
    TransactionRejected,
    ResourceNotFound,
    ResourceUnavailable,
    UnexpectedRpcErrorCode,
    InvalidBlockNumber,
    ParseError,
    ReachedMaxRetryLimit,
} || Allocator.Error || std.fmt.ParseIntError || http.Client.RequestError || std.Uri.ParseError
```

## InitOptions

### Properties

```zig
struct {
  /// Allocator used to manage the memory arena.
  allocator: Allocator
  /// The network config for the client to use.
  network_config: NetworkConfig
}
```

## Init
Init the client instance. Caller must call `deinit` to free the memory.\
Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.\
The client will handle request with 429 errors via exponential backoff but not the rest.

### Signature

```zig
pub fn init(opts: InitOptions) !*PubClient
```

## Deinit
Clears the memory arena and destroys all pointers created

### Signature

```zig
pub fn deinit(self: *PubClient) void
```

## ConnectRpcServer
Connects to the RPC server and relases the connection from the client pool.\
This is done so that future fetchs can use the connection that is already freed.

### Signature

```zig
pub fn connectRpcServer(self: *PubClient) !*HttpConnection
```

## BlobBaseFee
Grabs the current base blob fee.\
RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)

### Signature

```zig
pub fn blobBaseFee(self: *PubClient) !RPCResponse(Gwei)
```

## CreateAccessList
Create an accessList of addresses and storageKeys for an transaction to access
RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)

### Signature

```zig
pub fn createAccessList(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult)
```

## EstimateBlobMaxFeePerGas
Estimate the gas used for blobs
Uses `blobBaseFee` and `gasPrice` to calculate this estimation

### Signature

```zig
pub fn estimateBlobMaxFeePerGas(self: *PubClient) !Gwei
```

## EstimateFeesPerGas
Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.\
Uses the `baseFeePerGas` included in the block to calculate the gas fees.\
Will return an error in case the `baseFeePerGas` is null.

### Signature

```zig
pub fn estimateFeesPerGas(self: *PubClient, call_object: EthCall, base_fee_per_gas: ?Gwei) !EstimateFeeReturn
```

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.\
The transaction will not be added to the blockchain.\
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.\
RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

### Signature

```zig
pub fn estimateGas(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei)
```

## EstimateMaxFeePerGasManual
Estimates maxPriorityFeePerGas manually. If the node you are currently using
supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGasManual(self: *PubClient, base_fee_per_gas: ?Gwei) !Gwei
```

## EstimateMaxFeePerGas
Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGas(self: *PubClient) !RPCResponse(Gwei)
```

## FeeHistory
Returns historical gas information, allowing you to track trends over time.\
RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)

### Signature

```zig
pub fn feeHistory(self: *PubClient, blockCount: u64, newest_block: BlockNumberRequest, reward_percentil: ?[]const f64) !RPCResponse(FeeHistory)
```

## GetAccounts
Returns a list of addresses owned by client.\
RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)

### Signature

```zig
pub fn getAccounts(self: *PubClient) !RPCResponse([]const Address)
```

## GetAddressBalance
Returns the balance of the account of given address.\
RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)

### Signature

```zig
pub fn getAddressBalance(self: *PubClient, opts: BalanceRequest) !RPCResponse(Wei)
```

## GetAddressTransactionCount
Returns the number of transactions sent from an address.\
RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)

### Signature

```zig
pub fn getAddressTransactionCount(self: *PubClient, opts: BalanceRequest) !RPCResponse(u64)
```

## GetBlockByHash
Returns information about a block by hash.\
RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHash(self: *PubClient, opts: BlockHashRequest) !RPCResponse(Block)
```

## GetBlockByHashType
Returns information about a block by hash.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHashType(self: *PubClient, comptime T: type, opts: BlockHashRequest) !RPCResponse(T)
```

## GetBlockByNumber
Returns information about a block by number.\
RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumber(self: *PubClient, opts: BlockRequest) !RPCResponse(Block)
```

## GetBlockByNumberType
Returns information about a block by number.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumberType(self: *PubClient, comptime T: type, opts: BlockRequest) !RPCResponse(T)
```

## GetBlockNumber
Returns the number of most recent block.\
RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)

### Signature

```zig
pub fn getBlockNumber(self: *PubClient) !RPCResponse(u64)
```

## GetBlockTransactionCountByHash
Returns the number of transactions in a block from a block matching the given block hash.\
RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)

### Signature

```zig
pub fn getBlockTransactionCountByHash(self: *PubClient, block_hash: Hash) !RPCResponse(usize)
```

## GetBlockTransactionCountByNumber
Returns the number of transactions in a block from a block matching the given block number.\
RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)

### Signature

```zig
pub fn getBlockTransactionCountByNumber(self: *PubClient, opts: BlockNumberRequest) !RPCResponse(usize)
```

## GetChainId
Returns the chain ID used for signing replay-protected transactions.\
RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)

### Signature

```zig
pub fn getChainId(self: *PubClient) !RPCResponse(usize)
```

## GetClientVersion
Returns the node's client version
RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)

### Signature

```zig
pub fn getClientVersion(self: *PubClient) !RPCResponse([]const u8)
```

## GetContractCode
Returns code at a given address.\
RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)

### Signature

```zig
pub fn getContractCode(self: *PubClient, opts: BalanceRequest) !RPCResponse(Hex)
```

## GetFilterOrLogChanges
Polling method for a filter, which returns an array of logs which occurred since last poll or
Returns an array of all logs matching filter with given id depending on the selected method
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs

### Signature

```zig
pub fn getFilterOrLogChanges(self: *PubClient, filter_id: u128, method: EthereumRpcMethods) !RPCResponse(Logs)
```

## GetGasPrice
Returns an estimate of the current price per gas in wei.\
For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.\
RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)

### Signature

```zig
pub fn getGasPrice(self: *PubClient) !RPCResponse(Gwei)
```

## GetLogs
Returns an array of all logs matching a given filter object.\
RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)

### Signature

```zig
pub fn getLogs(self: *PubClient, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(Logs)
```

## GetNetworkListenStatus
Returns true if client is actively listening for network connections.\
RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)

### Signature

```zig
pub fn getNetworkListenStatus(self: *PubClient) !RPCResponse(bool)
```

## GetNetworkPeerCount
Returns number of peers currently connected to the client.\
RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)

### Signature

```zig
pub fn getNetworkPeerCount(self: *PubClient) !RPCResponse(usize)
```

## GetNetworkVersionId
Returns the current network id.\
RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)

### Signature

```zig
pub fn getNetworkVersionId(self: *PubClient) !RPCResponse(usize)
```

## GetProof
Returns the account and storage values, including the Merkle proof, of the specified account
RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)

### Signature

```zig
pub fn getProof(self: *PubClient, opts: ProofRequest, tag: ?ProofBlockTag) !RPCResponse(ProofResult)
```

## GetProtocolVersion
Returns the current Ethereum protocol version.\
RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)

### Signature

```zig
pub fn getProtocolVersion(self: *PubClient) !RPCResponse(u64)
```

## GetRawTransactionByHash
Returns the raw transaction data as a hexadecimal string for a given transaction hash
RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)

### Signature

```zig
pub fn getRawTransactionByHash(self: *PubClient, tx_hash: Hash) !RPCResponse(Hex)
```

## GetSha3Hash
Returns the Keccak256 hash of the given message.\
This converts the message into to hex values.\
RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)

### Signature

```zig
pub fn getSha3Hash(self: *PubClient, message: []const u8) !RPCResponse(Hash)
```

## GetStorage
Returns the value from a storage position at a given address.\
RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)

### Signature

```zig
pub fn getStorage(self: *PubClient, address: Address, storage_key: Hash, opts: BlockNumberRequest) !RPCResponse(Hash)
```

## GetSyncStatus
Returns null if the node has finished syncing. Otherwise it will return
the sync progress.\
RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)

### Signature

```zig
pub fn getSyncStatus(self: *PubClient) !?RPCResponse(SyncProgress)
```

## GetTransactionByBlockHashAndIndex
Returns information about a transaction by block hash and transaction index position.\
RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Transaction)
```

## GetTransactionByBlockHashAndIndexType
Returns information about a transaction by block hash and transaction index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndexType(self: *PubClient, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T)
```

## GetTransactionByBlockNumberAndIndex
### Signature

```zig
pub fn getTransactionByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction)
```

## GetTransactionByBlockNumberAndIndexType
Returns information about a transaction by block number and transaction index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)

### Signature

```zig
pub fn getTransactionByBlockNumberAndIndexType(self: *PubClient, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T)
```

## GetTransactionByHash
Returns the information about a transaction requested by transaction hash.\
RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHash(self: *PubClient, transaction_hash: Hash) !RPCResponse(Transaction)
```

## GetTransactionByHashType
Returns the information about a transaction requested by transaction hash.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHashType(self: *PubClient, comptime T: type, transaction_hash: Hash) !RPCResponse(T)
```

## GetTransactionReceipt
Returns the receipt of a transaction by transaction hash.\
RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn getTransactionReceipt(self: *PubClient, transaction_hash: Hash) !RPCResponse(TransactionReceipt)
```

## GetTxPoolContent
The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
The result is an object with two fields pending and queued.\
Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.\
These batches themselves are maps associating nonces with actual transactions.\
RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContent(self: *PubClient) !RPCResponse(TxPoolContent)
```

## GetTxPoolContentFrom
Retrieves the transactions contained within the txpool,
returning pending as well as queued transactions of this address, grouped by nonce
RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContentFrom(self: *PubClient, from: Address) !RPCResponse([]const PoolTransactionByNonce)
```

## GetTxPoolInspectStatus
The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.\
RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolInspectStatus(self: *PubClient) !RPCResponse(TxPoolInspect)
```

## GetTxPoolStatus
The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolStatus(self: *PubClient) !RPCResponse(TxPoolStatus)
```

## GetUncleByBlockHashAndIndex
Returns information about a uncle of a block by hash and uncle index position.\
RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Block)
```

## GetUncleByBlockHashAndIndexType
Returns information about a uncle of a block by hash and uncle index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndexType(self: *PubClient, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T)
```

## GetUncleByBlockNumberAndIndex
Returns information about a uncle of a block by number and uncle index position.\
RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !RPCResponse(Block)
```

## GetUncleByBlockNumberAndIndexType
Returns information about a uncle of a block by number and uncle index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndexType(self: *PubClient, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T)
```

## GetUncleCountByBlockHash
Returns the number of uncles in a block from a block matching the given block hash.\
RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)

### Signature

```zig
pub fn getUncleCountByBlockHash(self: *PubClient, block_hash: Hash) !RPCResponse(usize)
```

## GetUncleCountByBlockNumber
Returns the number of uncles in a block from a block matching the given block number.\
RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)

### Signature

```zig
pub fn getUncleCountByBlockNumber(self: *PubClient, opts: BlockNumberRequest) !RPCResponse(usize)
```

## Multicall3
Runs the selected multicall3 contracts.\
This enables to read from multiple contract by a single `eth_call`.\
Uses the contracts created [here](https://www.multicall3.com/)
To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)
You will need to decoded each of the `Result`.\
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
    self: *PubClient,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) !AbiDecoded([]const Result)
```

## NewBlockFilter
Creates a filter in the node, to notify when a new block arrives.\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)

### Signature

```zig
pub fn newBlockFilter(self: *PubClient) !RPCResponse(u128)
```

## NewLogFilter
Creates a filter object, based on filter options, to notify when the state changes (logs).\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)

### Signature

```zig
pub fn newLogFilter(self: *PubClient, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128)
```

## NewPendingTransactionFilter
Creates a filter in the node, to notify when new pending transactions arrive.\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)

### Signature

```zig
pub fn newPendingTransactionFilter(self: *PubClient) !RPCResponse(u128)
```

## SendEthCall
Executes a new message call immediately without creating a transaction on the block chain.\
Often used for executing read-only smart contract functions,
for example the balanceOf for an ERC-20 contract.\
Call object must be prefilled before hand. Including the data field.\
This will just make the request to the network.\
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn sendEthCall(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Hex)
```

## SendRawTransaction
Creates new message call transaction or a contract creation for signed transactions.\
Transaction must be serialized and signed before hand.\
RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

### Signature

```zig
pub fn sendRawTransaction(self: *PubClient, serialized_tx: Hex) !RPCResponse(Hash)
```

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.\
This is retry based on either the amount of `confirmations` given.\
If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.\
RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceipt(self: *PubClient, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt)
```

## WaitForTransactionReceiptType
Waits until a transaction gets mined and the receipt can be grabbed.\
This is retry based on either the amount of `confirmations` given.\
If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceiptType(self: *PubClient, comptime T: type, tx_hash: Hash, confirmations: u8) !RPCResponse(T)
```

## UninstallFilter
Uninstalls a filter with given id. Should always be called when watch is no longer needed.\
Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.\
RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)

### Signature

```zig
pub fn uninstallFilter(self: *PubClient, id: usize) !RPCResponse(bool)
```

## SendRpcRequest
Writes request to RPC server and parses the response according to the provided type.\
Handles 429 errors but not the rest.

### Signature

```zig
pub fn sendRpcRequest(self: *PubClient, comptime T: type, request: []const u8) !RPCResponse(T)
```

