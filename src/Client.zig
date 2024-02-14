const block = @import("meta/block.zig");
const http = std.http;
const log = @import("meta/log.zig");
const meta = @import("meta/meta.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");

// Types
const Allocator = std.mem.Allocator;
const Anvil = @import("tests/Anvil.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const BalanceBlockTag = block.BalanceBlockTag;
const BalanceRequest = block.BalanceRequest;
const Block = block.Block;
const BlockHashRequest = block.BlockHashRequest;
const BlockNumberRequest = block.BlockNumberRequest;
const BlockRequest = block.BlockRequest;
const BlockTag = block.BlockTag;
const Chains = types.PublicChains;
const EthCall = transaction.EthCall;
const EthCallHexed = transaction.EthCallHexed;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
const Extract = meta.Extract;
const Gwei = types.Gwei;
const Hex = types.Hex;
const HexRequestParameters = types.HexRequestParameters;
const Log = log.Log;
const LogFilterRequestParams = log.LogFilterRequestParams;
const LogRequest = log.LogRequest;
const LogRequestParams = log.LogRequestParams;
const Logs = log.Logs;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const Uri = std.Uri;
const Wei = types.Wei;

const httplog = std.log.scoped(.http);

pub const HttpClientError = error{ TransactionNotFound, FailedToGetReceipt, InvalidFilterId, InvalidLogRequestParams, TransactionReceiptNotFound, InvalidHash, UnexpectedErrorFound, UnableToFetchFeeInfoFromBlock, UnexpectedTooManyRequestError, InvalidInput, InvalidParams, InvalidRequest, InvalidAddress, InvalidBlockHash, InvalidBlockHashOrIndex, InvalidBlockNumberOrIndex, TooManyRequests, MethodNotFound, MethodNotSupported, RpcVersionNotSupported, LimitExceeded, TransactionRejected, ResourceNotFound, ResourceUnavailable, UnexpectedRpcErrorCode, InvalidBlockNumber, ParseError, ReachedMaxRetryLimit } || Allocator.Error || std.fmt.ParseIntError || http.Client.RequestError || std.Uri.ParseError;

pub const InitOptions = struct {
    /// Allocator used to manage the memory arena.
    allocator: Allocator,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// The interval to retry the request. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// Retry count for failed requests.
    retries: u8 = 5,
    /// Fork url for anvil to fork from
    uri: std.Uri,
};

/// This allocator will get set by the arena.
alloc: Allocator,
/// The arena where all allocations will leave.
arena: *ArenaAllocator,
/// The base fee multiplier used to estimate the gas fees in a transaction
base_fee_multiplier: f64,
/// The client chainId.
chain_id: usize,
/// The underlaying http client used to manage all the calls.
client: *http.Client,
/// The set of predifined headers use for the rpc calls.
headers: *http.Headers,
/// The interval to retry the request. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// Retry count for failed requests.
retries: u8,
/// The uri of the provided init string.
uri: Uri,

const PubClient = @This();

/// Init the client instance. Caller must call `deinit` to free the memory.
/// Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.
/// The client will handle request with 429 errors via exponential backoff but not the rest.
pub fn init(opts: InitOptions) !*PubClient {
    var pub_client = try opts.allocator.create(PubClient);
    errdefer opts.allocator.destroy(pub_client);

    pub_client.arena = try opts.allocator.create(ArenaAllocator);
    errdefer opts.allocator.destroy(pub_client.arena);

    pub_client.client = try opts.allocator.create(http.Client);
    errdefer opts.allocator.destroy(pub_client.client);

    pub_client.headers = try opts.allocator.create(http.Headers);
    errdefer opts.allocator.destroy(pub_client.arena);

    pub_client.arena.* = ArenaAllocator.init(opts.allocator);
    pub_client.alloc = pub_client.arena.allocator();
    errdefer pub_client.arena.deinit();

    pub_client.headers.* = try http.Headers.initList(pub_client.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    pub_client.client.* = http.Client{ .allocator = pub_client.alloc };

    pub_client.uri = opts.uri;

    const chain: Chains = opts.chain_id orelse .ethereum;
    const id = switch (chain) {
        inline else => |id| @intFromEnum(id),
    };

    pub_client.chain_id = id;
    pub_client.retries = opts.retries;
    pub_client.pooling_interval = opts.pooling_interval;
    pub_client.base_fee_multiplier = opts.base_fee_multiplier;

    return pub_client;
}
/// Clears the memory arena and destroys all pointers created
pub fn deinit(self: *PubClient) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
    allocator.destroy(self.headers);
    allocator.destroy(self.client);
    allocator.destroy(self);
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(self: *PubClient, call_object: EthCall, know_block: ?Block) !EstimateFeeReturn {
    const current_block = know_block orelse try self.getBlockByNumber(.{});

    switch (current_block) {
        inline else => |block_info| {
            switch (call_object) {
                .eip1559 => |tx| {
                    const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;
                    const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(current_block);
                    const max_fee = if (tx.maxFeePerGas) |max| max else base_fee + max_priority;

                    return .{ .eip1559 = .{ .max_fee_gas = max_fee, .max_priority_fee = max_priority } };
                },
                .legacy => |tx| {
                    const gas_price = if (tx.gasPrice) |price| price else try self.getGasPrice() * std.math.pow(u64, 10, 9);
                    const price = @divExact(gas_price * @as(u64, @intFromFloat(std.math.ceil(self.base_fee_multiplier * std.math.pow(f64, 10, 1)))), std.math.pow(u64, 10, 1));
                    return .{ .legacy = .{ .gas_price = price } };
                },
            }
        },
    }
}
/// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
/// The transaction will not be added to the blockchain.
/// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
/// for a variety of reasons including EVM mechanics and node performance.
///
/// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
pub fn estimateGas(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !Gwei {
    return try self.fetchCall(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *PubClient, know_block: ?Block) !Gwei {
    const current_block = know_block orelse try self.getBlockByNumber(.{});
    const gas_price = try self.getGasPrice();

    switch (current_block) {
        inline else => |block_info| {
            const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;

            const estimated = fee: {
                if (base_fee > gas_price) break :fee 0;

                break :fee gas_price - base_fee;
            };

            return estimated;
        },
    }
}
/// Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.
pub fn estimateMaxFeePerGas(self: *PubClient) !Gwei {
    return try self.fetchWithEmptyArgs(Gwei, .eth_maxPriorityFeePerGas);
}
/// Returns a list of addresses owned by client.
///
/// RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)
pub fn getAccounts(self: *PubClient) ![]const Hex {
    return try self.fetchWithEmptyArgs([]const Hex, .eth_accounts);
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *PubClient, opts: BalanceRequest) !Wei {
    return try self.fetchByAddress(Wei, opts, .eth_getBalance);
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *PubClient, opts: BalanceRequest) !u64 {
    return try self.fetchByAddress(u64, opts, .eth_getTransactionCount);
}
/// Returns information about a block by hash.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(self: *PubClient, opts: BlockHashRequest) !Block {
    if (!utils.isHash(opts.block_hash)) return error.InvalidHash;
    const include = opts.include_transaction_objects orelse false;

    const Params = std.meta.Tuple(&[_]type{ Hex, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash, .id = self.chain_id };

    const request_block = try self.fetchBlock(request);
    const block_info = request_block orelse return error.InvalidBlockHash;

    return block_info;
}
/// Returns information about a block by number.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumber(self: *PubClient, opts: BlockRequest) !Block {
    const tag: BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ Hex, bool });
    const params: Params = .{ block_number, include };
    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByNumber, .id = self.chain_id };

    const request_block = try self.fetchBlock(request);
    const block_info = request_block orelse return error.InvalidBlockNumber;

    return block_info;
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockNumber(self: *PubClient) !u64 {
    return try self.fetchWithEmptyArgs(u64, .eth_blockNumber);
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *PubClient, block_hash: Hex) !usize {
    return try self.fetchByBlockHash(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *PubClient, opts: BlockNumberRequest) !usize {
    return try self.fetchByBlockNumber(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *PubClient) !usize {
    return try self.fetchWithEmptyArgs(usize, .eth_chainId);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *PubClient, opts: BalanceRequest) !Hex {
    return try self.fetchByAddress(Hex, opts, .eth_getCode);
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *PubClient, filter_id: usize, method: Extract(EthereumRpcMethods, "eth_getFilterChanges,eth_getFilterLogs")) !Logs {
    const filter_i = try std.fmt.allocPrint(self.alloc, "0x{x}", .{filter_id});

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{filter_i}, .method = method, .id = self.chain_id };

    const possible_filter = try self.fetchLogs(HexRequestParameters, request);
    const filter = possible_filter orelse return error.InvalidFilterId;

    return filter;
}
/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *PubClient) !Gwei {
    return try self.fetchWithEmptyArgs(u64, .eth_gasPrice);
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *PubClient, opts: LogRequestParams) !Logs {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;
    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;

    const request: EthereumRequest([]const LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_getLogs, .id = self.chain_id };

    const possible_logs = try self.fetchLogs([]const LogRequest, request);
    const logs = possible_logs orelse return error.InvalidLogRequestParams;

    return logs;
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *PubClient, block_hash: Hex, index: usize) !Transaction {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    const possible_tx = try self.fetchTransaction(?Transaction, request);
    const tx = possible_tx orelse return error.TransactionNotFound;

    return tx;
}
/// Returns information about a transaction by block number and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !Transaction {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockNumberAndIndex, .id = self.chain_id };

    const possible_tx = try self.fetchTransaction(?Transaction, request);
    const tx = possible_tx orelse return error.TransactionNotFound;

    return tx;
}
/// Returns the information about a transaction requested by transaction hash.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHash(self: *PubClient, transaction_hash: Hex) !Transaction {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionByHash, .id = self.chain_id };

    const possible_tx = try self.fetchTransaction(?Transaction, request);
    const tx = possible_tx orelse return error.TransactionNotFound;

    return tx;
}
/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(self: *PubClient, transaction_hash: Hex) !TransactionReceipt {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionReceipt, .id = self.chain_id };

    const possible_receipt = try self.fetchTransaction(?TransactionReceipt, request);
    const receipt = possible_receipt orelse return error.TransactionReceiptNotFound;

    return receipt;
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *PubClient, block_hash: Hex, index: usize) !Block {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ Hex, Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockHashAndIndex, .id = self.chain_id };

    const request_block = try self.fetchBlock(request);
    const block_info = request_block orelse return error.InvalidBlockHashOrIndex;

    return block_info;
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !Block {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ Hex, Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockNumberAndIndex, .id = self.chain_id };

    const request_block = try self.fetchBlock(request);
    const block_info = request_block orelse return error.InvalidBlockNumberOrIndex;

    return block_info;
}
/// Returns the number of uncles in a block from a block matching the given block hash.
///
/// RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)
pub fn getUncleCountByBlockHash(self: *PubClient, block_hash: Hex) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getUncleCountByBlockHash);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *PubClient, opts: BlockNumberRequest) !usize {
    return try self.fetchByBlockNumber(opts, .eth_getUncleCountByBlockNumber);
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *PubClient) !usize {
    return try self.fetchWithEmptyArgs(usize, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *PubClient, opts: LogFilterRequestParams) !usize {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;
    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;

    const request: EthereumRequest([]const LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_newFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(usize, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *PubClient) !usize {
    return try self.fetchWithEmptyArgs(usize, .eth_newPendingTransactionFilter);
}
/// Executes a new message call immediately without creating a transaction on the block chain.
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !Hex {
    return try self.fetchCall(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *PubClient, serialized_hex_tx: Hex) !Hex {
    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{serialized_hex_tx}, .method = .eth_sendRawTransaction, .id = self.chain_id };

    return try self.fetchTransaction(Hex, request);
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(self: *PubClient, tx_hash: Hex, confirmations: u8) !?TransactionReceipt {
    var tx: ?Transaction = null;
    var block_number = try self.getBlockNumber();
    var receipt: ?TransactionReceipt = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
        error.TransactionReceiptNotFound => null,
        else => return err,
    };

    // The receipt can be null here
    if (confirmations == 0)
        return receipt;

    var retries: u8 = 0;
    var valid_confirmations: u8 = 0;
    while (true) : (retries += 1) {
        if (retries - valid_confirmations > self.retries)
            return error.FailedToGetReceipt;

        if (receipt) |tx_receipt| {
            // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
            if (valid_confirmations > confirmations and (tx_receipt.blockNumber != null or block_number - tx_receipt.blockNumber.? + 1 < confirmations)) {
                receipt = tx_receipt;
                break;
            } else {
                valid_confirmations += 1;
                std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                continue;
            }
        }

        if (tx == null) {
            tx = self.getTransactionByHash(tx_hash) catch |err| switch (err) {
                // If it fails we keep trying
                error.TransactionNotFound => {
                    std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                    continue;
                },
                else => return err,
            };

            switch (tx.?) {
                // Changes the block search to the one of the found transaction
                inline else => |tx_object| {
                    if (tx_object.blockNumber) |number| block_number = number;
                },
            }

            receipt = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
                error.TransactionReceiptNotFound => {
                    // Need to check if the transaction was replaced.
                    const current_block = try self.getBlockByNumber(.{ .include_transaction_objects = true });

                    // TODO: Find cleaner way to do this.
                    const replaced: ?Transaction = outer: {
                        switch (tx.?) {
                            inline else => |transactions| {
                                switch (current_block) {
                                    inline else => |pending| {
                                        for (pending.transactions.objects) |pending_transaction| {
                                            switch (pending_transaction) {
                                                inline else => |tx_pending| {
                                                    if (std.mem.eql(u8, transactions.from, tx_pending.from) and tx_pending.nonce == transactions.nonce)
                                                        break :outer pending_transaction;
                                                },
                                            }
                                        }
                                        break :outer null;
                                    },
                                }
                            },
                        }
                    };

                    // If the transaction was replace return it's receipt. Otherwise try again.
                    if (replaced) |replaced_tx| {
                        receipt = switch (replaced_tx) {
                            inline else => |tx_object| try self.getTransactionReceipt(tx_object.hash),
                        };

                        httplog.debug("Transaction was replace by a newer one", .{});

                        switch (replaced_tx) {
                            inline else => |replacement| switch (tx.?) {
                                inline else => |original| {
                                    if (std.mem.eql(u8, replacement.from, original.from) and replacement.value == original.value)
                                        httplog.debug("Original transaction was repriced", .{});

                                    if (replacement.to) |replaced_to| {
                                        if (std.mem.eql(u8, replacement.from, replaced_to) and replacement.value == 0)
                                            httplog.debug("Original transaction was canceled", .{});
                                    }
                                },
                            },
                        }

                        // Here we are sure to have a valid receipt.
                        const valid_receipt = receipt.?;
                        // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
                        if (valid_confirmations > confirmations and (valid_receipt.blockNumber != null or block_number - valid_receipt.blockNumber.? + 1 < confirmations))
                            break;
                    }

                    std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                    continue;
                },
                else => return err,
            };

            const valid_receipt = receipt.?;
            // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
            if (valid_confirmations > confirmations and (valid_receipt.blockNumber != null or block_number - valid_receipt.blockNumber.? + 1 < confirmations)) {
                break;
            } else {
                valid_confirmations += 1;
                std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                continue;
            }
        }
    }

    return receipt;
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstalllFilter(self: *PubClient, id: usize) !bool {
    const filter_id = try std.fmt.allocPrint(self.alloc, "0x{x}", .{id});

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{filter_id}, .method = .eth_uninstallFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(bool, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}
/// Switch the client network and chainId.
pub fn switchNetwork(self: *PubClient, new_chain_id: Chains, new_url: []const u8) void {
    self.chain_id = @intFromEnum(new_chain_id);

    const uri = try Uri.parse(new_url);
    self.uri = uri;
}

fn fetchByBlockNumber(self: *PubClient, opts: BlockNumberRequest, method: EthereumRpcMethods) !usize {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{block_number}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(usize, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchByBlockHash(self: *PubClient, block_hash: []const u8, method: EthereumRpcMethods) !usize {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{block_hash}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(usize, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchByAddress(self: *PubClient, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) !T {
    if (!try utils.isAddress(self.alloc, opts.address)) return error.InvalidAddress;
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{ opts.address, block_number }, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(T, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchWithEmptyArgs(self: *PubClient, comptime T: type, method: EthereumRpcMethods) !T {
    const Params = std.meta.Tuple(&[_]type{});
    const request: EthereumRequest(Params) = .{ .params = .{}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(T, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchBlock(self: *PubClient, request: anytype) !?Block {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(?Block, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchTransaction(self: *PubClient, comptime T: type, request: EthereumRequest(HexRequestParameters)) !T {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(T, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchLogs(self: *PubClient, comptime T: type, request: EthereumRequest(T)) !?Logs {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(?Logs, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn fetchCall(self: *PubClient, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) !T {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const call = try utils.hexifyEthCall(self.alloc, call_object);

    const Params = std.meta.Tuple(&[_]type{ EthCallHexed, Hex });
    const request: EthereumRequest(Params) = .{ .params = .{ call, block_number }, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });
        switch (req.status) {
            .ok => return try self.parseRPCEvent(T, req.body.?),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn parseRPCEvent(self: *PubClient, comptime T: type, request: []const u8) !T {
    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(T), self.alloc, request, .{ .allocate = .alloc_always }) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, request, .{ .ignore_unknown_fields = true })) |result| {
            httplog.debug("RPC error response: {s}", .{result.@"error".message});

            if (result.@"error".data) |data|
                httplog.debug("RPC error response data: {s}", .{data});

            // Converts the rpc error codes to zig errors
            return switch (result.@"error".code) {
                // This will only affect WS connections but we need to handle it here too
                .TooManyRequests => error.UnexpectedTooManyRequestError,
                .InvalidInput => error.InvalidInput,
                .MethodNotFound => error.MethodNotFound,
                .ResourceNotFound => error.ResourceNotFound,
                .InvalidRequest => error.InvalidRequest,
                .ParseError => error.ParseError,
                .LimitExceeded => error.LimitExceeded,
                .InvalidParams => error.InvalidParams,
                .InternalError => error.InternalError,
                .MethodNotSupported => error.MethodNotSupported,
                .ResourceUnavailable => error.ResourceNotFound,
                .TransactionRejected => error.TransactionRejected,
                .RpcVersionNotSupported => error.RpcVersionNotSupported,
                _ => error.UnexpectedRpcErrorCode,
            };
        } else |_| return error.UnexpectedErrorFound;
    };

    return parsed.result;
}

test "GetBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_req = try pub_client.getBlockNumber();

    try testing.expectEqual(19062632, block_req);
}

test "GetChainId" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const chain = try pub_client.getChainId();

    try testing.expectEqual(1, chain);
}

test "GetBlock" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockByNumber(.{});
    try testing.expect(block_info == .blockMerge);
    try testing.expectEqual(block_info.blockMerge.number.?, 19062632);
    try testing.expectEqualStrings(block_info.blockMerge.hash.?, "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");

    const block_old = try pub_client.getBlockByNumber(.{ .block_number = 696969 });
    try testing.expect(block_old == .block);
}

test "GetBlockByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockByHash(.{ .block_hash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(block_info == .blockMerge);
    try testing.expectEqual(block_info.blockMerge.number.?, 19062632);
}

test "GetBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getBlockTransactionCountByNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByNumber(.{});
    try testing.expect(block_info != 0);
}

test "getBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getAccounts" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const accounts = try pub_client.getAccounts();
    try testing.expect(accounts.len != 0);
}

test "gasPrice" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const gasPrice = try pub_client.getGasPrice();
    try testing.expect(gasPrice != 0);
}

test "getCode" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const code = try pub_client.getContractCode(.{ .address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" });
    try testing.expectEqualStrings(code, "0x6060604052600436106100af576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306fdde03146100b9578063095ea7b31461014757806318160ddd146101a157806323b872dd146101ca5780632e1a7d4d14610243578063313ce5671461026657806370a082311461029557806395d89b41146102e2578063a9059cbb14610370578063d0e30db0146103ca578063dd62ed3e146103d4575b6100b7610440565b005b34156100c457600080fd5b6100cc6104dd565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561010c5780820151818401526020810190506100f1565b50505050905090810190601f1680156101395780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561015257600080fd5b610187600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061057b565b604051808215151515815260200191505060405180910390f35b34156101ac57600080fd5b6101b461066d565b6040518082815260200191505060405180910390f35b34156101d557600080fd5b610229600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061068c565b604051808215151515815260200191505060405180910390f35b341561024e57600080fd5b61026460048080359060200190919050506109d9565b005b341561027157600080fd5b610279610b05565b604051808260ff1660ff16815260200191505060405180910390f35b34156102a057600080fd5b6102cc600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610b18565b6040518082815260200191505060405180910390f35b34156102ed57600080fd5b6102f5610b30565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561033557808201518184015260208101905061031a565b50505050905090810190601f1680156103625780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561037b57600080fd5b6103b0600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091908035906020019091905050610bce565b604051808215151515815260200191505060405180910390f35b6103d2610440565b005b34156103df57600080fd5b61042a600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610be3565b6040518082815260200191505060405180910390f35b34600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055503373ffffffffffffffffffffffffffffffffffffffff167fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c346040518082815260200191505060405180910390a2565b60008054600181600116156101000203166002900480601f0160208091040260200160405190810160405280929190818152602001828054600181600116156101000203166002900480156105735780601f1061054857610100808354040283529160200191610573565b820191906000526020600020905b81548152906001019060200180831161055657829003601f168201915b505050505081565b600081600460003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b60003073ffffffffffffffffffffffffffffffffffffffff1631905090565b600081600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054101515156106dc57600080fd5b3373ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16141580156107b457507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205414155b156108cf5781600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020541015151561084457600080fd5b81600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055505b81600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000828254039250508190555081600360008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a3600190509392505050565b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410151515610a2757600080fd5b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055503373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501515610ab457600080fd5b3373ffffffffffffffffffffffffffffffffffffffff167f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65826040518082815260200191505060405180910390a250565b600260009054906101000a900460ff1681565b60036020528060005260406000206000915090505481565b60018054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610bc65780601f10610b9b57610100808354040283529160200191610bc6565b820191906000526020600020905b815481529060010190602001808311610ba957829003601f168201915b505050505081565b6000610bdb33848461068c565b905092915050565b60046020528160005260406000206020528060005260406000206000915091505054815600a165627a7a72305820deb4c2ccab3c2fdca32ab3f46728389c2fe2c165d5fafa07661e4e004f6c344a0029");
}

test "getAddressBalance" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const address = try pub_client.getAddressBalance(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(address, try utils.parseEth(10000));
}

test "getUncleCountByBlockHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const uncle = try pub_client.getUncleCountByBlockHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expectEqual(uncle, 0);
}

test "getUncleCountByBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const uncle = try pub_client.getUncleCountByBlockNumber(.{});
    try testing.expectEqual(uncle, 0);
}

test "getLogs" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const logs = try pub_client.getLogs(.{ .blockHash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(logs.len != 0);
}

test "getTransactionByBlockNumberAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const tx = try pub_client.getTransactionByBlockNumberAndIndex(.{ .block_number = 16777215 }, 0);
    try testing.expect(tx == .eip1559);
}

test "getTransactionByBlockHashAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const tx = try pub_client.getTransactionByBlockHashAndIndex("0xf34c3c11b35466e5595e077239e6b25a7c3ec07a214b2492d42ba6d73d503a1b", 0);
    try testing.expect(tx == .eip1559);
}

test "getAddressTransactionCount" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const nonce = try pub_client.getAddressTransactionCount(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(nonce, 605);
}

test "getTransactionByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const eip1559 = try pub_client.getTransactionByHash("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(eip1559 == .eip1559);

    // Remove because they fail on CI run.
    // const legacy = try pub_client.getTransactionByHash("0xf9ffe354d26160616844278c4fcbfe0eaa5589da48bc1359eda81fc1ce18b51a");
    // try testing.expect(legacy == .legacy);
    //
    // const tx_untyped = try pub_client.getTransactionByHash("0x0bad3271acf0f10e56caf39187c956583710e1295ee3369a442beda0a666b27a");
    // try testing.expect(tx_untyped == .untyped);
}

test "getTransactionReceipt" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const receipt = try pub_client.getTransactionReceipt("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(receipt.status != null);

    // Pre-Byzantium
    const legacy = try pub_client.getTransactionReceipt("0x4dadc87da2b7c47125fb7e4102d95457830e44d2fbcd45537d91f8be1e5f6130");
    try testing.expect(legacy.root != null);
}

test "estimateGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const gas = try pub_client.estimateGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, .{});
    try testing.expect(gas != 0);
}

test "estimateFeesPerGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const gas = try pub_client.estimateFeesPerGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, null);
    try testing.expect(gas.eip1559.max_fee_gas != 0);
    try testing.expect(gas.eip1559.max_priority_fee != 0);
}

test "estimateMaxFeePerGasManual" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client = try PubClient.init(.{ .allocator = std.testing.allocator, .uri = uri });
    defer pub_client.deinit();

    const gas = try pub_client.estimateMaxFeePerGasManual(null);
    try testing.expect(gas != 0);
}
