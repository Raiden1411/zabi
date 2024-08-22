## HttpClientError

## InitOptions

## Init
Init the client instance. Caller must call `deinit` to free the memory.\
Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.\
The client will handle request with 429 errors via exponential backoff but not the rest.

## Deinit
Clears the memory arena and destroys all pointers created

## ConnectRpcServer
Connects to the RPC server and relases the connection from the client pool.\
This is done so that future fetchs can use the connection that is already freed.

## BlobBaseFee
Grabs the current base blob fee.\
RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)

## CreateAccessList
Create an accessList of addresses and storageKeys for an transaction to access
RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)

## EstimateBlobMaxFeePerGas
Estimate the gas used for blobs
Uses `blobBaseFee` and `gasPrice` to calculate this estimation

## EstimateFeesPerGas
Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.\
Uses the `baseFeePerGas` included in the block to calculate the gas fees.\
Will return an error in case the `baseFeePerGas` is null.

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.\
The transaction will not be added to the blockchain.\
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.\
RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

## EstimateMaxFeePerGasManual
Estimates maxPriorityFeePerGas manually. If the node you are currently using
supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.

## EstimateMaxFeePerGas
Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.

## FeeHistory
Returns historical gas information, allowing you to track trends over time.\
RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)

## GetAccounts
Returns a list of addresses owned by client.\
RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)

## GetAddressBalance
Returns the balance of the account of given address.\
RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)

## GetAddressTransactionCount
Returns the number of transactions sent from an address.\
RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)

## GetBlockByHash
Returns information about a block by hash.\
RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

## GetBlockByHashType
Returns information about a block by hash.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

## GetBlockByNumber
Returns information about a block by number.\
RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

## GetBlockByNumberType
Returns information about a block by number.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

## GetBlockNumber
Returns the number of most recent block.\
RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)

## GetBlockTransactionCountByHash
Returns the number of transactions in a block from a block matching the given block hash.\
RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)

## GetBlockTransactionCountByNumber
Returns the number of transactions in a block from a block matching the given block number.\
RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)

## GetChainId
Returns the chain ID used for signing replay-protected transactions.\
RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)

## GetClientVersion
Returns the node's client version
RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)

## GetContractCode
Returns code at a given address.\
RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)

## GetFilterOrLogChanges
Polling method for a filter, which returns an array of logs which occurred since last poll or
Returns an array of all logs matching filter with given id depending on the selected method
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs

## GetGasPrice
Returns an estimate of the current price per gas in wei.\
For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.\
RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)

## GetLogs
Returns an array of all logs matching a given filter object.\
RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)

## GetNetworkListenStatus
Returns true if client is actively listening for network connections.\
RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)

## GetNetworkPeerCount
Returns number of peers currently connected to the client.\
RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)

## GetNetworkVersionId
Returns the current network id.\
RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)

## GetProof
Returns the account and storage values, including the Merkle proof, of the specified account
RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)

## GetProtocolVersion
Returns the current Ethereum protocol version.\
RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)

## GetRawTransactionByHash
Returns the raw transaction data as a hexadecimal string for a given transaction hash
RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)

## GetSha3Hash
Returns the Keccak256 hash of the given message.\
This converts the message into to hex values.\
RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)

## GetStorage
Returns the value from a storage position at a given address.\
RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)

## GetSyncStatus
Returns null if the node has finished syncing. Otherwise it will return
the sync progress.\
RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)

## GetTransactionByBlockHashAndIndex
Returns information about a transaction by block hash and transaction index position.\
RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

## GetTransactionByBlockHashAndIndexType
Returns information about a transaction by block hash and transaction index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

## GetTransactionByBlockNumberAndIndex

## GetTransactionByBlockNumberAndIndexType
Returns information about a transaction by block number and transaction index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)

## GetTransactionByHash
Returns the information about a transaction requested by transaction hash.\
RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

## GetTransactionByHashType
Returns the information about a transaction requested by transaction hash.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

## GetTransactionReceipt
Returns the receipt of a transaction by transaction hash.\
RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

## GetTxPoolContent
The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
The result is an object with two fields pending and queued.\
Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.\
These batches themselves are maps associating nonces with actual transactions.\
RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

## GetTxPoolContentFrom
Retrieves the transactions contained within the txpool,
returning pending as well as queued transactions of this address, grouped by nonce
RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

## GetTxPoolInspectStatus
The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.\
RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

## GetTxPoolStatus
The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.\
RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

## GetUncleByBlockHashAndIndex
Returns information about a uncle of a block by hash and uncle index position.\
RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

## GetUncleByBlockHashAndIndexType
Returns information about a uncle of a block by hash and uncle index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

## GetUncleByBlockNumberAndIndex
Returns information about a uncle of a block by number and uncle index position.\
RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

## GetUncleByBlockNumberAndIndexType
Returns information about a uncle of a block by number and uncle index position.\
Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.\
RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

## GetUncleCountByBlockHash
Returns the number of uncles in a block from a block matching the given block hash.\
RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)

## GetUncleCountByBlockNumber
Returns the number of uncles in a block from a block matching the given block number.\
RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)

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

## NewBlockFilter
Creates a filter in the node, to notify when a new block arrives.\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)

## NewLogFilter
Creates a filter object, based on filter options, to notify when the state changes (logs).\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)

## NewPendingTransactionFilter
Creates a filter in the node, to notify when new pending transactions arrive.\
To check if the state has changed, call `getFilterOrLogChanges`.\
RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)

## SendEthCall
Executes a new message call immediately without creating a transaction on the block chain.\
Often used for executing read-only smart contract functions,
for example the balanceOf for an ERC-20 contract.\
Call object must be prefilled before hand. Including the data field.\
This will just make the request to the network.\
RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

## SendRawTransaction
Creates new message call transaction or a contract creation for signed transactions.\
Transaction must be serialized and signed before hand.\
RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.\
This is retry based on either the amount of `confirmations` given.\
If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.\
RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

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

## UninstallFilter
Uninstalls a filter with given id. Should always be called when watch is no longer needed.\
Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.\
RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)

## SwitchNetwork
Switch the client network and chainId.\
Invalidates all of the client connections and pointers.\
This will also try to automatically connect to the new RPC.

## SendRpcRequest
Writes request to RPC server and parses the response according to the provided type.\
Handles 429 errors but not the rest.

