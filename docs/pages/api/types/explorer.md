## ExplorerResponse
The json response from a etherscan like explorer

### Signature

```zig
pub fn ExplorerResponse(comptime T: type) type
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

## ExplorerSuccessResponse
The json success response from a etherscan like explorer

### Signature

```zig
pub fn ExplorerSuccessResponse(comptime T: type) type
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

## ExplorerErrorResponse

The json error response from a etherscan like explorer

### Properties

```zig
status: u1 = 0
message: []const u8
result: []const u8
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

## ExplorerRequestResponse
The response represented as a union of possible responses.\
Returns the `@error` field from json parsing in case the message is `NOK`.

### Signature

```zig
pub fn ExplorerRequestResponse(comptime T: type) type
```

## EndPoints

Set of predefined block explorer endpoints.\
For now these must have support for TLS v1.3
This only supports etherscan like block explorers.

### Properties

```zig
/// Assign it null if you would like to set the default endpoint value.
arbitrum: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
arbitrum_sepolia: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
base: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
bsc: ?[]const u8
/// Currently doesn't support tls v1.3 so it won't work until
/// zig gets support for tls v1.2
/// Assign it null if you would like to set the default endpoint value.
ethereum: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
fantom: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
localhost: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
moonbeam: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
optimism: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
polygon: ?[]const u8
/// Assign it null if you would like to set the default endpoint value.
sepolia: ?[]const u8
```

### GetEndpoint
Gets the associated endpoint or the default one.

### Signature

```zig
pub fn getEndpoint(self: @This()) []const u8
```

## MultiAddressBalance

Result from the api call of `getMultiAddressBalance`

### Properties

```zig
/// The address of the account.
account: Address
/// The balance of the account.
balance: u256
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

## TokenExplorerTransaction

Token transaction represented by a `etherscan` like client.

### Properties

```zig
/// The block number where the transaction was mined
blockNumber: u64
/// The time when the transaction was commited.
timeStamp: u64
/// The transaction hash
hash: Hash
/// The transaction nonce.
nonce: u64
/// The blockHash this transaction was mined.
blockHash: Hash
/// The sender of this transaction
from: Address
/// The contract address in case it exists.
contractAddress: Address
/// The target address.
to: Address
/// The value sent. Only used for erc20 tokens.
value: ?u256 = null
/// The token Id. Only used for erc721 and erc1155 tokens.
tokenId: ?u256 = null
/// The token name.
tokenName: []const u8
/// The token symbol.
tokenSymbol: []const u8
/// The token decimal. Only used for erc20 and erc721 tokens.
tokenDecimal: ?u8 = null
/// The index of this transaction on the mempool
transactionIndex: usize
/// The gas limit of the transaction
gas: u64
/// The gas price of this transaction.
gasPrice: u64
/// The gas used by the transaction.
gasUsed: u64
/// The cumulative gas used by the transaction.
cumulativeGasUsed: u64
/// Input field that has been deprecated.
input: []const u8 = "deprecated"
/// The total number of confirmations
confirmations: usize
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

## InternalExplorerTransaction

Internal transaction represented by a `etherscan` like client.

### Properties

```zig
/// The block number where the transaction was mined
blockNumber: u64
/// The time when the transaction was commited.
timeStamp: u64
/// The transaction hash
hash: Hash
/// The sender of this transaction
from: Address
/// The target address.
to: ?Address
/// The value sent.
value: u256
/// The contract address in case it exists.
contractAddress: ?Address
/// The transaction data.
input: ?[]u8
/// The transaction type.
type: enum { call }
/// The gas limit of the transaction
gas: u64
/// The gas used by the transaction.
gasUsed: u64
/// If the transaction failed. Use `@bitCast` to convert to `bool`.
isError: u1
/// The status of the receipt. Use `@bitCast` to convert to `bool`.
traceId: []const u8
/// The error code in case it exists.
errCode: ?i64
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

## ExplorerTransaction

Transaction represented by a `etherscan` like client.

### Properties

```zig
/// The block number where the transaction was mined
blockNumber: u64
/// The time when the transaction was commited.
timeStamp: u64
/// The transaction hash
hash: Hash
/// The transaction nonce
nonce: u64
/// The block hash
blockHash: Hash
/// Index of the transaction in the memory pool
transactionIndex: usize
/// The sender of this transaction
from: Address
/// The target address.
to: ?Address
/// The value sent.
value: u256
/// The gas limit of the transaction
gas: u64
/// The gas price of the transaction.
gasPrice: u64
/// If the transaction failed. Use `@bitCast` to convert to `bool`.
isError: u1
/// The status of the receipt. Use `@bitCast` to convert to `bool`.
txreceipt_status: u1
/// The transaction data.
input: ?[]u8
/// The gas used by the transaction.
gasUsed: u64
/// The number of confirmations.
confirmations: u64
/// The methodId of the contract if it interacted with any.
methodId: ?[]u8
/// The contract method name if the transaction interacted with one.
functionName: ?[]const u8
/// The contract address in case it exists.
contractAddress: ?Address = null
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

## GetSourceResult

### Properties

```zig
/// The contract's source code.
SourceCode: []const u8
/// The contract's ABI.
ABI: Abi
/// The contract name.
ContractName: []const u8
/// The compiler version that was used.
CompilerVersion: SemanticVersion
/// The number of optimizations used.
OptimizationUsed: usize
/// The amount of runs of optimizations.
Runs: usize
/// The constructor arguments if any were used.
ConstructorArguments: ?[]const u8
/// The EVM version used.
EVMVersion: enum { Default }
/// The library used if any.
Library: ?[]const u8
/// The license type used by the contract.
LicenseType: []const u8
/// If it's a proxy contract or not. Can be `@bitCast` to bool
Proxy: u1
/// The implementation if it exists.
Implementation: ?[]const u8
/// The bzzr swarm source.
SwarmSource: Uri
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

## Erc1155TokenEventRequest

## TokenEventRequest

## TransactionListRequest

## MultiAddressBalanceRequest

## AddressBalanceRequest

## RangeRequest

## ContractCreationResult

### Properties

```zig
/// The contract address
contractAddress: Address
/// The contract creator
contractCreator: Address
/// The creation transaction hash
txHash: Hash
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

## TransactionStatus

### Properties

```zig
/// If the transaction reverted.
isError: u1
/// The error message in case it reverted.
errDescription: ?[]const u8
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

## ReceiptStatus

### Properties

```zig
/// The receipt status
status: ?u1
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

## BlockRewards

The block reward endpoint response.

### Properties

```zig
/// The block number of the reward.
blockNumber: u64
/// The timestamp of the reward.
timeStamp: u64
/// The block miner.
blockMiner: Address
/// The reward value.
blockReward: u256
/// The uncles block rewards.
uncles: []const BlockRewards
/// The reward value included in uncle blocks.
uncleInclusionReward: u256
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

## LogRequest

`getLogs` request via a block explorer.

## ExplorerLog

Zig struct representation of the log explorer response.

### Properties

```zig
/// The contract address
address: Address
/// The emitted log topics from the contract call.
topics: []const ?Hash
/// The data sent via the log
data: []u8
/// The block number this log was emitted.
blockNumber: ?u64
/// The block hash where this log was emitted.
blockHash: ?Hash
/// The timestamp where this log was emitted.
timeStamp: u64
/// The gas price of the transaction this log was emitted in.
gasPrice: u64
/// The gas used by the transaction this log was emitted in.
gasUsed: u64
/// The log index.
logIndex: ?usize
/// The transaction hash that emitted this log.
transactionHash: ?Hash
/// The transaction index in the memory pool location.
transactionIndex: ?usize
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

## BlockCountdown

### Properties

```zig
/// The current block in the node.
CurrentBlock: u64
/// The target block.
CountdownBlock: u64
/// The number of blocks remaining between `CurrentBlock` and `CountdownBlock`.
RemainingBlock: u64
/// The seconds until `CountdownBlock` is reached.
EstimateTimeInSec: f64
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

## BlocktimeRequest

## TokenBalanceRequest

## EtherPriceResponse

### Properties

```zig
/// The ETH-BTC price.
ethbtc: f64
/// The ETH-BTC price timestamp.
ethbtc_timestamp: u64
/// The ETH-USD price.
ethusd: f64
/// The ETH-USD price timestamp.
ethusd_timestamp: u64
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

## GasOracle

### Properties

```zig
/// The last block where the oracle recorded the information.
LastBlock: u64
/// Safe gas price to used to get transaciton mined.
SafeGasPrice: u64
/// Proposed gas price.
ProposeGasPrice: u64
/// Fast gas price.
FastGasPrice: u64
/// Suggest transacition base fee.
suggestBaseFee: f64
/// Gas used ratio.
gasUsedRatio: []const f64
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

