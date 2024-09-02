## FetchErrors

Set of errors while fetching from a json rpc http endpoint.

```zig
Allocator.Error || HttpClient.RequestError || HttpClient.Request.WaitError ||
    HttpClient.Request.FinishError || HttpClient.Request.ReadError || Uri.ParseError || error{StreamTooLong}
```

## SendRequestErrors

Set of errors when sending a request.

```zig
FetchErrors || error{ UnexpectedServerResponse, UnexpectedErrorFound, ReachedMaxRetryLimit, InvalidRequest }
```

## BasicRequestErrors

Set of generic errors when sending a request.

```zig
SendRequestErrors || error{NoSpaceLeft}
```

## Modules

The block explorer modules.

### Properties

```zig
enum {
  account
  contract
  transaction
  block
  logs
  stats
  gastracker
  token
}
```

## Actions

The block explorer actions.

### Properties

```zig
enum {
  balance
  balancemulti
  txlist
  txlistinternal
  tokentx
  tokennfttx
  token1155tx
  tokenbalance
  balancehistory
  tokenbalancehistory
  addresstokenbalance
  addresstokennftbalance
  addresstokennftinventory
  getabi
  getsourcecode
  getcontractcreation
  getstatus
  gettxreceiptstatus
  getblockreward
  getblockcountdown
  getblocknobytime
  dailyavgblocksize
  dailyblkcount
  dailyuncleblkcount
  getLogs
  gasestimate
  gasoracle
  tokensupply
  ethprice
  ethsupply
  dailyblockrewards
  dailyavgblocktime
  tokensupplyhistory
  dailyavggaslimit
  dailygasused
  dailyavggasprice
  ethdailyprice
  dailytxnfee
  dailynewaddress
  dailynetutilization
  dailytx
  tokenholderlist
  tokeninfo
}
```

## InitOpts

The client init options

### Properties

```zig
struct {
  allocator: Allocator
  /// The Explorer api key.
  apikey: []const u8
  /// Set of supported endpoints.
  endpoint: EndPoints = .{ .optimism = null }
  /// The max size that the fetch call can use
  max_append_size: usize = std.math.maxInt(u16)
  /// The number of retries for the client to make on 429 errors.
  retries: usize = 5
}
```

## QueryParameters

Used by the `Explorer` client to build the uri query parameters.

### Properties

```zig
struct {
  /// The module of the endpoint to target.
  module: Modules
  /// The action endpoint to target.
  action: Actions
  /// Set of pagination options.
  options: QueryOptions
  /// Endpoint api key.
  apikey: []const u8
}
```

### BuildQuery
Build the query based on the provided `value` and it's inner state.
Uses the `QueryWriter` to build the searchUrlParams.

### Signature

```zig
pub fn buildQuery(self: @This(), value: anytype, writer: anytype) @TypeOf(writer).Error!void
```

### BuildDefaultQuery
Build the query parameters without any provided values.
Uses the `QueryWriter` to build the searchUrlParams.

### Signature

```zig
pub fn buildDefaultQuery(self: @This(), writer: anytype) @TypeOf(writer).Error!void
```

## Init
Creates the initial client state.\
This client only supports the free api endpoints via the api. We will not support PRO methods.

But `zabi` has all the tools you will need to create the methods to target those endpoints.
This only supports etherscan like block explorers.

**Example**
```zig
var explorer = Explorer.init(.{.allocator = std.heap.page_allocator, .apikey = "YOUR_API_KEY"});
defer explorer.deinit();
```

### Signature

```zig
pub fn init(opts: InitOpts) Explorer
```

## Deinit
Deinits the http/s server.

### Signature

```zig
pub fn deinit(self: *Explorer) void
```

## GetAbi
Queries the api endpoint to find the `address` contract ABI.

### Signature

```zig
pub fn getAbi(self: *Explorer, address: Address) (BasicRequestErrors || ParseError(Scanner))!ExplorerResponse(Abi)
```

## GetAddressBalance
Queries the api endpoint to find the `address` balance at the specified `tag`

### Signature

```zig
pub fn getAddressBalance(self: *Explorer, request: AddressBalanceRequest) BasicRequestErrors!ExplorerResponse(u256)
```

## GetBlockCountDown
Queries the api endpoint to find the block reward at the specified `block_number`

### Signature

```zig
pub fn getBlockCountDown(self: *Explorer, block_number: u64) BasicRequestErrors!ExplorerResponse(BlockCountDown)
```

## GetBlockNumberByTimestamp
Queries the api endpoint to find the block reward at the specified `block_number`

### Signature

```zig
pub fn getBlockNumberByTimestamp(self: *Explorer, request: BlocktimeRequest) BasicRequestErrors!ExplorerResponse(u64)
```

## GetBlockReward
Queries the api endpoint to find the block reward at the specified `block_number`

### Signature

```zig
pub fn getBlockReward(self: *Explorer, block_number: u64) BasicRequestErrors!ExplorerResponse(BlockRewards)
```

## GetContractCreation
Queries the api endpoint to find the creation tx address from the target contract addresses.

### Signature

```zig
pub fn getContractCreation(self: *Explorer, addresses: []const Address) BasicRequestErrors!ExplorerResponse([]const ContractCreationResult)
```

## GetEstimationOfConfirmation
Queries the api endpoint to find the `address` balance at the specified `tag`

### Signature

```zig
pub fn getEstimationOfConfirmation(self: *Explorer, gas_price: u64) BasicRequestErrors!ExplorerResponse(u64)
```

## GetErc20TokenBalance
Queries the api endpoint to find the `address` erc20 token balance.

### Signature

```zig
pub fn getErc20TokenBalance(self: *Explorer, request: TokenBalanceRequest) BasicRequestErrors!ExplorerResponse(u256)
```

## GetErc20TokenSupply
Queries the api endpoint to find the `address` erc20 token supply.

### Signature

```zig
pub fn getErc20TokenSupply(self: *Explorer, address: Address) BasicRequestErrors!ExplorerResponse(u256)
```

## GetErc20TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

### Signature

```zig
pub fn getErc20TokenTransferEvents(
    self: *Explorer,
    request: TokenEventRequest,
    options: QueryOptions,
) BasicRequestErrors!ExplorerResponse([]const TokenExplorerTransaction)
```

## GetErc721TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

### Signature

```zig
pub fn getErc721TokenTransferEvents(
    self: *Explorer,
    request: TokenEventRequest,
    options: QueryOptions,
) BasicRequestErrors!ExplorerResponse([]const TokenExplorerTransaction)
```

## GetErc1155TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

### Signature

```zig
pub fn getErc1155TokenTransferEvents(
    self: *Explorer,
    request: Erc1155TokenEventRequest,
    options: QueryOptions,
) BasicRequestErrors!ExplorerResponse([]const TokenExplorerTransaction)
```

## GetEtherPrice
Queries the api endpoint to find the `address` erc20 token balance.

### Signature

```zig
pub fn getEtherPrice(self: *Explorer) BasicRequestErrors!ExplorerResponse(EtherPriceResponse)
```

## GetInternalTransactionList
Queries the api endpoint to find the `address` internal transaction list based on a block range.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`.

### Signature

```zig
pub fn getInternalTransactionList(
    self: *Explorer,
    request: TransactionListRequest,
    options: QueryOptions,
) BasicRequestErrors!ExplorerResponse([]const InternalExplorerTransaction)
```

## GetInternalTransactionListByHash
Queries the api endpoint to find the internal transactions from a transaction hash.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`.

### Signature

```zig
pub fn getInternalTransactionListByHash(self: *Explorer, tx_hash: Hash) BasicRequestErrors!ExplorerResponse([]const InternalExplorerTransaction)
```

## GetInternalTransactionListByRange
Queries the api endpoint to find the `address` balances at the specified `tag`

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

### Signature

```zig
pub fn getInternalTransactionListByRange(
    self: *Explorer,
    request: RangeRequest,
    options: QueryOptions,
) BasicRequestErrors!ExplorerResponse([]const InternalExplorerTransaction)
```

## GetLogs
Queries the api endpoint to find the logs at the target `address` based on the provided block range.

### Signature

```zig
pub fn getLogs(self: *Explorer, request: LogRequest, options: QueryOptions) BasicRequestErrors!ExplorerResponse([]const ExplorerLog)
```

## GetMultiAddressBalance
Queries the api endpoint to find the `address` balances at the specified `tag`

### Signature

```zig
pub fn getMultiAddressBalance(self: *Explorer, request: MultiAddressBalanceRequest) BasicRequestErrors!ExplorerResponse([]const MultiAddressBalance)
```

## GetSourceCode
Queries the api endpoint to find the `address` contract source information if it's present.
The api might send the result with empty field in case the source information is not present.
This will cause the json parse to fail.

### Signature

```zig
pub fn getSourceCode(self: *Explorer, address: Address) BasicRequestErrors!ExplorerResponse([]const GetSourceResult)
```

## GetTotalEtherSupply
Queries the api endpoint to find the `address` erc20 token balance.

### Signature

```zig
pub fn getTotalEtherSupply(self: *Explorer) BasicRequestErrors!ExplorerResponse(u256)
```

## GetTransactionList
Queries the api endpoint to find the `address` transaction list based on a block range.

This can fail because the response can be higher than `max_append_size`.
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

### Signature

```zig
pub fn getTransactionList(self: *Explorer, request: TransactionListRequest, options: QueryOptions) BasicRequestErrors!ExplorerResponse([]const ExplorerTransaction)
```

## GetTransactionReceiptStatus
Queries the api endpoint to find the transaction receipt status based on the provided `hash`

### Signature

```zig
pub fn getTransactionReceiptStatus(self: *Explorer, hash: Hash) BasicRequestErrors!ExplorerResponse(ReceiptStatus)
```

## GetTransactionStatus
Queries the api endpoint to find the transaction status based on the provided `hash`

### Signature

```zig
pub fn getTransactionStatus(self: *Explorer, hash: Hash) BasicRequestErrors!ExplorerResponse(TransactionStatus)
```

## SendRequest
Writes request to endpoint and parses the response according to the provided type.
Handles 429 errors but not the rest.

Builds the uri from the endpoint's api url plus the query parameters from the provided `value`
and possible set `QueryOptions`. The current max buffer size is 4096.

`value` must be a non tuple struct type.

### Signature

```zig
pub fn sendRequest(self: *Explorer, comptime T: type, uri: Uri) SendRequestErrors!ExplorerResponse(T)
```

