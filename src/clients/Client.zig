const block = @import("../types/block.zig");
const http = std.http;
const log = @import("../types/log.zig");
const meta = @import("../meta/utils.zig");
const proof = @import("../types/proof.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AccessListResult = transaction.AccessListResult;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @import("../tests/Anvil.zig");
const BalanceBlockTag = block.BalanceBlockTag;
const BalanceRequest = block.BalanceRequest;
const Block = block.Block;
const BlockHashRequest = block.BlockHashRequest;
const BlockNumberRequest = block.BlockNumberRequest;
const BlockRequest = block.BlockRequest;
const BlockTag = block.BlockTag;
const Chains = types.PublicChains;
const EthCall = transaction.EthCall;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
const Extract = meta.Extract;
const FeeHistory = transaction.FeeHistory;
const FetchResult = http.Client.FetchResult;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const HttpConnection = http.Client.Connection;
const Log = log.Log;
const LogRequest = log.LogRequest;
const LogTagRequest = log.LogTagRequest;
const Logs = log.Logs;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const RPCResponse = types.RPCResponse;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const Tuple = std.meta.Tuple;
const Uri = std.Uri;
const Wei = types.Wei;

const httplog = std.log.scoped(.http);

pub const HttpClientError = error{ TransactionNotFound, FailedToGetReceipt, EvmFailedToExecute, InvalidFilterId, InvalidLogRequestParams, TransactionReceiptNotFound, InvalidHash, UnexpectedErrorFound, UnableToFetchFeeInfoFromBlock, UnexpectedTooManyRequestError, InvalidInput, InvalidParams, InvalidRequest, InvalidAddress, InvalidBlockHash, InvalidBlockHashOrIndex, InvalidBlockNumberOrIndex, TooManyRequests, MethodNotFound, MethodNotSupported, RpcVersionNotSupported, LimitExceeded, TransactionRejected, ResourceNotFound, ResourceUnavailable, UnexpectedRpcErrorCode, InvalidBlockNumber, ParseError, ReachedMaxRetryLimit } || Allocator.Error || std.fmt.ParseIntError || http.Client.RequestError || std.Uri.ParseError;

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
allocator: Allocator,
/// The base fee multiplier used to estimate the gas fees in a transaction
base_fee_multiplier: f64,
/// The client chainId.
chain_id: usize,
/// The underlaying http client used to manage all the calls.
client: *http.Client,
/// Connection used as a reference for http client connections
connection: *HttpConnection,
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
pub fn init(self: *PubClient, opts: InitOptions) !void {
    const client = try opts.allocator.create(http.Client);
    errdefer opts.allocator.destroy(client);

    const chain: Chains = opts.chain_id orelse .ethereum;
    const id = switch (chain) {
        inline else => |id| @intFromEnum(id),
    };

    self.* = .{
        .uri = opts.uri,
        .allocator = opts.allocator,
        .chain_id = id,
        .retries = opts.retries,
        .pooling_interval = opts.pooling_interval,
        .base_fee_multiplier = opts.base_fee_multiplier,
        .client = client,
        .connection = undefined,
    };

    self.client.* = http.Client{ .allocator = self.allocator };
    errdefer self.client.deinit();

    self.connection = try self.connectRpcServer();
}
/// Clears the memory arena and destroys all pointers created
pub fn deinit(self: *PubClient) void {
    self.client.deinit();

    self.allocator.destroy(self.client);

    self.* = undefined;
}
/// Connects to the RPC server and relases the connection from the client pool.
/// This is done so that future fetchs can use the connection that is already freed.
pub fn connectRpcServer(self: *PubClient) !*HttpConnection {
    const scheme = std.http.Client.protocol_map.get(self.uri.scheme) orelse return error.UnsupportedSchema;
    const port: u16 = self.uri.port orelse switch (scheme) {
        .plain => 80,
        .tls => 443,
    };

    var retries: usize = 0;
    const connection = while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.FailedToConnect;

        switch (retries) {
            0...2 => {},
            else => {
                const sleep_timing: u64 = @min(10_000, self.pooling_interval * retries);
                std.time.sleep(sleep_timing * std.time.ns_per_ms);
            },
        }

        if (scheme == .tls and @atomicLoad(bool, &self.client.next_https_rescan_certs, .acquire)) {
            self.client.ca_bundle_mutex.lock();
            defer self.client.ca_bundle_mutex.unlock();

            if (self.client.next_https_rescan_certs) {
                self.client.ca_bundle.rescan(self.allocator) catch |err| {
                    httplog.debug("Failed to rescan certificate bundle: {s}", .{@errorName(err)});
                    continue;
                };
                @atomicStore(bool, &self.client.next_https_rescan_certs, false, .release);
            }
        }
        const connection = self.client.connect(self.uri.host.?, port, scheme) catch |err| {
            httplog.debug("Connection failed: {s}", .{@errorName(err)});
            continue;
        };

        break connection;
    };

    self.client.connection_pool.release(self.allocator, connection);

    return connection;
}
/// Grabs the current base blob fee.
///
/// RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)
pub fn blobBaseFee(self: *PubClient) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_blobBaseFee);
}
/// Create an accessList of addresses and storageKeys for an transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}
/// Estimate the gas used for blobs
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation
pub fn estimateBlobMaxFeePerGas(self: *PubClient) !Gwei {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else base.response - gas_price.response;
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(self: *PubClient, call_object: EthCall, base_fee_per_gas: ?Gwei) !EstimateFeeReturn {
    const current_fee: ?Gwei = block: {
        if (base_fee_per_gas) |fee| break :block fee;

        const rpc_block = try self.getBlockByNumber(.{});
        rpc_block.deinit();

        break :block switch (rpc_block.response) {
            inline else => |block_info| block_info.baseFeePerGas,
        };
    };

    switch (call_object) {
        .london => |tx| {
            const base_fee = current_fee orelse return error.UnableToFetchFeeInfoFromBlock;
            const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(base_fee);

            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(base_fee)) * self.base_fee_multiplier);
            const max_fee = if (tx.maxFeePerGas) |max| max else @as(Gwei, @intFromFloat(mutiplier)) + max_priority;

            return .{
                .london = .{
                    .max_fee_gas = max_fee,
                    .max_priority_fee = max_priority,
                },
            };
        },
        .legacy => |tx| {
            const gas_price = gas: {
                if (tx.gasPrice) |price| break :gas price;
                const gas_price = try self.getGasPrice();
                defer gas_price.deinit();

                break :gas gas_price.response;
            };
            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(gas_price)) * self.base_fee_multiplier);
            const price: u64 = @intFromFloat(mutiplier);
            return .{
                .legacy = .{ .gas_price = price },
            };
        },
    }
}
/// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
/// The transaction will not be added to the blockchain.
/// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
/// for a variety of reasons including EVM mechanics and node performance.
///
/// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
pub fn estimateGas(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
    return try self.sendEthCallRequest(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *PubClient, base_fee_per_gas: ?Gwei) !Gwei {
    const current_fee: ?Gwei = block: {
        if (base_fee_per_gas) |fee| break :block fee;

        const rpc_block = try self.getBlockByNumber(.{});
        rpc_block.deinit();

        break :block switch (rpc_block.response) {
            inline else => |block_info| block_info.baseFeePerGas,
        };
    };
    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    const base_fee = current_fee orelse return error.UnableToFetchFeeInfoFromBlock;

    return if (base_fee > gas_price.response) 0 else gas_price.response - base_fee;
}
/// Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.
pub fn estimateMaxFeePerGas(self: *PubClient) !RPCResponse(Gwei) {
    return try self.sendBasicRequest(Gwei, .eth_maxPriorityFeePerGas);
}
/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(self: *PubClient, blockCount: u64, newest_block: BlockNumberRequest, reward_percentil: ?[]const f64) !RPCResponse(FeeHistory) {
    const tag: BalanceBlockTag = newest_block.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (newest_block.block_number) |number| {
        const request: EthereumRequest(struct { u64, u64, ?[]const f64 }) = .{
            .params = .{ blockCount, number, reward_percentil },
            .method = .eth_feeHistory,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { u64, BalanceBlockTag, ?[]const f64 }) = .{
            .params = .{ blockCount, tag, reward_percentil },
            .method = .eth_feeHistory,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(FeeHistory, buf_writter.getWritten());
}
/// Returns a list of addresses owned by client.
///
/// RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)
pub fn getAccounts(self: *PubClient) !RPCResponse([]const Address) {
    return self.sendBasicRequest([]const Address, .eth_accounts);
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *PubClient, opts: BalanceRequest) !RPCResponse(Wei) {
    return self.sendAddressRequest(Wei, opts, .eth_getBalance);
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *PubClient, opts: BalanceRequest) !RPCResponse(u64) {
    return self.sendAddressRequest(u64, opts, .eth_getTransactionCount);
}
/// Returns information about a block by hash.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(self: *PubClient, opts: BlockHashRequest) !RPCResponse(Block) {
    const include = opts.include_transaction_objects orelse false;

    const request: EthereumRequest(struct { Hash, bool }) = .{
        .params = .{ opts.block_hash, include },
        .method = .eth_getBlockByHash,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const request_block = try self.sendRpcRequest(?Block, buf_writter.getWritten());
    errdefer request_block.deinit();

    const block_info = request_block.response orelse return error.InvalidBlockHash;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}
/// Returns information about a block by number.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumber(self: *PubClient, opts: BlockRequest) !RPCResponse(Block) {
    const tag: BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, bool }) = .{
            .params = .{ number, include },
            .method = .eth_getBlockByNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BlockTag, bool }) = .{
            .params = .{ tag, include },
            .method = .eth_getBlockByNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const request_block = try self.sendRpcRequest(?Block, buf_writter.getWritten());
    errdefer request_block.deinit();

    const block_info = request_block.response orelse return error.InvalidBlockNumber;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockNumber(self: *PubClient) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blockNumber);
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *PubClient, block_hash: Hash) !RPCResponse(usize) {
    return try self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *PubClient, opts: BlockNumberRequest) !RPCResponse(usize) {
    return try self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *PubClient) !RPCResponse(usize) {
    return try self.sendBasicRequest(usize, .eth_chainId);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *PubClient, opts: BalanceRequest) !RPCResponse(Hex) {
    return try self.sendAddressRequest(Hex, opts, .eth_getCode);
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *PubClient, filter_id: usize, method: Extract(EthereumRpcMethods, "eth_getFilterChanges,eth_getFilterLogs")) !RPCResponse(Logs) {
    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const request: EthereumRequest(struct { usize }) = .{
        .params = .{filter_id},
        .method = method,
        .id = self.chain_id,
    };

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_filter = try self.sendRpcRequest(Logs, buf_writter.getWritten());
    const filter = possible_filter orelse return error.InvalidFilterId;

    return filter;
}
/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *PubClient) !RPCResponse(Gwei) {
    return try self.sendBasicRequest(u64, .eth_gasPrice);
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *PubClient, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(Logs) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { LogTagRequest }) = .{
            .params = .{.{
                .fromBlock = request_tag,
                .toBlock = request_tag,
                .address = opts.address,
                .blockHash = opts.blockHash,
                .topics = opts.topics,
            }},
            .method = .eth_getLogs,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_getLogs,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const possible_logs = try self.sendRpcRequest(?Logs, buf_writter.getWritten());
    errdefer possible_logs.deinit();

    const logs = possible_logs.response orelse return error.InvalidLogRequestParams;

    return .{
        .arena = possible_logs.arena,
        .response = logs,
    };
}
/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(self: *PubClient, opts: ProofRequest, tag: ?ProofBlockTag) !RPCResponse(ProofResult) {
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { Address, []const Hash, block.ProofBlockTag }) = .{
            .params = .{ opts.address, opts.storageKeys, request_tag },
            .method = .eth_getProof,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const number = opts.blockNumber orelse return error.ExpectBlockNumberOrTag;

        const request: EthereumRequest(struct { Address, []const Hash, u64 }) = .{
            .params = .{ opts.address, opts.storageKeys, number },
            .method = .eth_getProof,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(ProofResult, buf_writter.getWritten());
}
/// Returns the value from a storage position at a given address.
///
/// RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)
pub fn getStorage(self: *PubClient, address: Address, storage_key: Hash, opts: BlockNumberRequest) !RPCResponse(Hash) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, Hash, u64 }) = .{
            .params = .{ address, storage_key, number },
            .method = .eth_getStorageAt,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, Hash, BalanceBlockTag }) = .{
            .params = .{ address, storage_key, tag },
            .method = .eth_getStorageAt,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Transaction) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getTransactionByBlockHashAndIndex,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_tx = try self.sendRpcRequest(?Transaction, buf_writter.getWritten());
    errdefer possible_tx.deinit();

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}
/// Returns information about a transaction by block number and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const possible_tx = try self.sendRpcRequest(?Transaction, buf_writter.getWritten());
    errdefer possible_tx.deinit();

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}
/// Returns the information about a transaction requested by transaction hash.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHash(self: *PubClient, transaction_hash: Hash) !RPCResponse(Transaction) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionByHash,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_tx = try self.sendRpcRequest(?Transaction, buf_writter.getWritten());
    errdefer possible_tx.deinit();

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}
/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(self: *PubClient, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionReceipt,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_receipt = try self.sendRpcRequest(?TransactionReceipt, buf_writter.getWritten());
    errdefer possible_receipt.deinit();

    const receipt = possible_receipt.response orelse return error.TransactionReceiptNotFound;

    return .{
        .arena = possible_receipt.arena,
        .response = receipt,
    };
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Block) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getUncleByBlockHashAndIndex,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const request_block = try self.sendRpcRequest(?Block, buf_writter.getWritten());
    errdefer request_block.deinit();

    const block_info = request_block.response orelse return error.InvalidBlockHashOrIndex;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !RPCResponse(Block) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const request_block = try self.sendRpcRequest(?Block, buf_writter.getWritten());
    errdefer request_block.deinit();

    const block_info = request_block.response orelse return error.InvalidBlockNumberOrIndex;

    return .{
        .arena = request_block.arena,
        .response = block_info,
    };
}
/// Returns the number of uncles in a block from a block matching the given block hash.
///
/// RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)
pub fn getUncleCountByBlockHash(self: *PubClient, block_hash: Hash) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *PubClient, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *PubClient) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *PubClient, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(usize) {
    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (tag) |request_tag| {
        const request: EthereumRequest(struct { LogTagRequest }) = .{
            .params = .{.{
                .fromBlock = request_tag,
                .toBlock = request_tag,
                .address = opts.address,
                .blockHash = opts.blockHash,
                .topics = opts.topics,
            }},
            .method = .eth_newFilter,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_newFilter,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(usize, buf_writter.getWritten());
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *PubClient) !RPCResponse(usize) {
    return try self.sendBasicRequest(usize, .eth_newPendingTransactionFilter);
}
/// Executes a new message call immediately without creating a transaction on the block chain.
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Hex) {
    return try self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *PubClient, serialized_tx: Hex) !RPCResponse(Hash) {
    const request: EthereumRequest(struct { Hex }) = .{
        .params = .{serialized_tx},
        .method = .eth_sendRawTransaction,
        .id = self.chain_id,
    };

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(self: *PubClient, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
    var tx: ?RPCResponse(Transaction) = null;
    defer if (tx) |tx_res| tx_res.deinit();

    const block_number_request = try self.getBlockNumber();
    defer block_number_request.deinit();

    var block_number = block_number_request.response;

    var receipt: ?RPCResponse(TransactionReceipt) = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
        error.TransactionReceiptNotFound => null,
        else => return err,
    };
    errdefer if (receipt) |tx_receipt| tx_receipt.deinit();

    if (receipt) |tx_receipt| {
        if (confirmations == 0)
            return tx_receipt;
    }

    var retries: u8 = if (receipt != null) 1 else 0;
    var valid_confirmations: u8 = if (receipt != null) 1 else 0;
    while (true) : (retries += 1) {
        if (retries - valid_confirmations > self.retries)
            return error.FailedToGetReceipt;

        if (receipt) |tx_receipt| {
            const number: ?u64 = switch (tx_receipt.response) {
                inline else => |all| all.blockNumber,
            };
            // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
            if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations)) {
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
        }

        switch (tx.?.response) {
            // Changes the block search to the one of the found transaction
            inline else => |tx_object| {
                if (tx_object.blockNumber) |number| block_number = number;
            },
        }

        receipt = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
            error.TransactionReceiptNotFound => {
                // Need to check if the transaction was replaced.
                const current_block = try self.getBlockByNumber(.{ .include_transaction_objects = true });
                defer current_block.deinit();

                const tx_info: struct { from: Address, nonce: u64 } = switch (tx.?.response) {
                    inline else => |transactions| .{ .from = transactions.from, .nonce = transactions.nonce },
                };

                const block_transactions = switch (current_block.response) {
                    inline else => |blocks| if (blocks.transactions) |block_txs| block_txs else {
                        std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                        continue;
                    },
                };

                const pending_transaction = switch (block_transactions) {
                    .hashes => {
                        std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                        continue;
                    },
                    .objects => |tx_objects| tx_objects,
                };

                const replaced: ?Transaction = for (pending_transaction) |pending| {
                    const pending_info: struct { from: Address, nonce: u64 } = switch (pending) {
                        inline else => |transactions| .{ .from = transactions.from, .nonce = transactions.nonce },
                    };

                    if (std.mem.eql(u8, &tx_info.from, &pending_info.from) and pending_info.nonce == tx_info.nonce)
                        break pending;
                } else null;

                // If the transaction was replace return it's receipt. Otherwise try again.
                if (replaced) |replaced_tx| {
                    receipt = switch (replaced_tx) {
                        inline else => |tx_object| try self.getTransactionReceipt(tx_object.hash),
                    };

                    httplog.debug("Transaction was replace by a newer one", .{});

                    switch (replaced_tx) {
                        inline else => |replacement| switch (tx.?.response) {
                            inline else => |original| {
                                if (std.mem.eql(u8, &replacement.from, &original.from) and replacement.value == original.value)
                                    httplog.debug("Original transaction was repriced", .{});

                                if (replacement.to) |replaced_to| {
                                    if (std.mem.eql(u8, &replacement.from, &replaced_to) and replacement.value == 0)
                                        httplog.debug("Original transaction was canceled", .{});
                                }
                            },
                        },
                    }

                    // Here we are sure to have a valid receipt.
                    const valid_receipt = receipt.?.response;
                    const number: ?u64 = switch (valid_receipt) {
                        inline else => |all| all.blockNumber,
                    };
                    // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
                    if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations))
                        break;
                }

                std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                continue;
            },
            else => return err,
        };

        const valid_receipt = receipt.?.response;
        const number: ?u64 = switch (valid_receipt) {
            inline else => |all| all.blockNumber,
        };
        // If it has enough confirmations we break out of the loop and return. Otherwise it keep pooling
        if (valid_confirmations > confirmations and (number != null or block_number - number.? + 1 < confirmations)) {
            break;
        } else {
            valid_confirmations += 1;
            std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
            continue;
        }
    }

    return if (receipt) |tx_receipt| tx_receipt else error.FailedToGetReceipt;
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstalllFilter(self: *PubClient, id: usize) !RPCResponse(bool) {
    const request: EthereumRequest(struct { usize }) = .{
        .params = .{id},
        .method = .eth_uninstallFilter,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(bool, buf_writter.getWritten());
}
/// Switch the client network and chainId.
/// Invalidates all of the client connections and pointers.
///
/// This will also try to automatically connect to the new RPC.
pub fn switchNetwork(self: *PubClient, new_chain_id: Chains, new_url: []const u8) void {
    self.chain_id = @intFromEnum(new_chain_id);

    const uri = try Uri.parse(new_url);
    self.uri = uri;

    var next_node = self.client.connection_pool.free.first;

    while (next_node) |node| {
        defer self.allocator.destroy(node);
        next_node = node.next;

        node.data.close(self.allocator);
    }

    next_node = self.client.connection_pool.used;

    while (next_node) |node| {
        defer self.allocator.destroy(node);
        next_node = node.next;

        node.data.close(self.allocator);
    }

    self.connection.* = try self.connectRpcServer();
}
/// Writes request to RPC server and parses the response according to the provided type.
/// Handles 429 errors but not the rest.
pub fn sendRpcRequest(self: *PubClient, comptime T: type, request: []const u8) !RPCResponse(T) {
    httplog.debug("Preparing to send request body: {s}", .{request});

    var body = std.ArrayList(u8).init(self.allocator);
    defer body.deinit();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        const req = try self.internalFetch(request, &body);

        switch (req.status) {
            .ok => {
                const res_body = try body.toOwnedSlice();
                defer self.allocator.free(res_body);

                httplog.debug("Got response from server: {s}", .{res_body});

                return self.parseRPCEvent(T, res_body);
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                // Clears any message that was written
                body.clearRetainingCapacity();
                try body.ensureTotalCapacity(0);

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => return error.InvalidRequest,
        }
    }
}

fn sendBlockNumberRequest(self: *PubClient, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(usize) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64 }) = .{
            .params = .{number},
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag }) = .{
            .params = .{tag},
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(usize, buf_writter.getWritten());
}

fn sendBlockHashRequest(self: *PubClient, block_hash: Hash, method: EthereumRpcMethods) !RPCResponse(usize) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{block_hash},
        .method = method,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(usize, buf_writter.getWritten());
}

fn sendAddressRequest(self: *PubClient, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(T, buf_writter.getWritten());
}

fn sendBasicRequest(self: *PubClient, comptime T: type, method: EthereumRpcMethods) !RPCResponse(T) {
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = method,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(T, buf_writter.getWritten());
}

fn sendEthCallRequest(self: *PubClient, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(T, buf_writter.getWritten());
}
/// Internal PubClient fetch. Optimized for our use case.
fn internalFetch(self: *PubClient, payload: []const u8, body: *std.ArrayList(u8)) !FetchResult {
    var server_header_buffer: [16 * 1024]u8 = undefined;

    var request = try self.client.open(.POST, self.uri, .{
        .server_header_buffer = &server_header_buffer,
        .redirect_behavior = .unhandled,
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .connection = self.connection,
    });
    defer {
        if (!request.response.parser.done) {
            self.connection.closing = true;
        }
        if (self.client.connection_pool.used.len != 0) {
            self.client.connection_pool.release(self.allocator, self.connection);
        }
    }

    request.transfer_encoding = .{ .content_length = payload.len };

    try request.send(.{});

    try request.writeAll(payload);

    try request.finish();
    try request.wait();

    const max_size = 2 * 1024 * 1024;
    try request.reader().readAllArrayList(body, max_size);

    return .{
        .status = request.response.status,
    };
}

fn parseRPCEvent(self: *PubClient, comptime T: type, request: []const u8) !RPCResponse(T) {
    const parsed = std.json.parseFromSlice(EthereumResponse(T), self.allocator, request, .{ .allocate = .alloc_always }) catch return error.UnexpectedErrorFound;

    switch (parsed.value) {
        .success => |response| return RPCResponse(T).fromJson(parsed.arena, response.result),
        .@"error" => |response| {
            errdefer parsed.deinit();
            httplog.debug("RPC error response: {s}", .{response.@"error".message});

            if (response.@"error".data) |data|
                httplog.debug("RPC error data response: {s}", .{data});

            switch (response.@"error".code) {
                .ContractErrorCode => return error.EvmFailedToExecute,
                // This will only affect WS connections but we need to handle it here too
                .TooManyRequests => return error.UnexpectedTooManyRequestError,
                .InvalidInput => return error.InvalidInput,
                .MethodNotFound => return error.MethodNotFound,
                .ResourceNotFound => return error.ResourceNotFound,
                .InvalidRequest => return error.InvalidRequest,
                .ParseError => return error.ParseError,
                .LimitExceeded => return error.LimitExceeded,
                .InvalidParams => return error.InvalidParams,
                .InternalError => return error.InternalError,
                .MethodNotSupported => return error.MethodNotSupported,
                .ResourceUnavailable => return error.ResourceNotFound,
                .TransactionRejected => return error.TransactionRejected,
                .RpcVersionNotSupported => return error.RpcVersionNotSupported,
                _ => return error.UnexpectedRpcErrorCode,
            }
        },
    }
}

test "GetBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const block_req = try pub_client.getBlockNumber();
    defer block_req.deinit();

    try testing.expectEqual(19062632, block_req.response);
}

test "GetChainId" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const chain = try pub_client.getChainId();
    defer chain.deinit();

    try testing.expectEqual(1, chain.response);
}

test "GetBlock" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const block_request = try pub_client.getBlockByNumber(.{});
        defer block_request.deinit();

        const block_info = block_request.response;

        try testing.expect(block_info == .beacon);
        try testing.expectEqual(block_info.beacon.number.?, 19062632);

        const slice = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8";
        try testing.expectEqualSlices(u8, &block_info.beacon.hash.?, &try utils.hashToBytes(slice));
    }
    {
        const block_request = try pub_client.getBlockByNumber(.{ .include_transaction_objects = true });
        defer block_request.deinit();

        try testing.expect(block_request.response.beacon.transactions != null);
        try testing.expect(block_request.response.beacon.transactions.? == .objects);
    }

    // const block_old = try pub_client.getBlockByNumber(.{ .block_number = 1 });
    // try testing.expect(block_old == .legacy);
}

test "CreateAccessList" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    var buffer: [100]u8 = undefined;
    const bytes = try std.fmt.hexToBytes(&buffer, "608060806080608155");
    {
        const accessList = try pub_client.createAccessList(
            .{ .london = .{ .from = try utils.addressToBytes("0xaeA8F8f781326bfE6A7683C2BD48Dd6AA4d3Ba63"), .data = bytes } },
            .{},
        );
        defer accessList.deinit();

        try testing.expect(accessList.response.accessList.len != 0);
    }
    {
        const accessList = try pub_client.createAccessList(
            .{ .london = .{ .from = try utils.addressToBytes("0xaeA8F8f781326bfE6A7683C2BD48Dd6AA4d3Ba63"), .data = bytes } },
            .{ .block_number = 19062632 },
        );
        defer accessList.deinit();

        try testing.expect(accessList.response.accessList.len != 0);
    }
}

test "FeeHistory" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const fee_history = try pub_client.feeHistory(5, .{}, &[_]f64{ 20, 30 });
        defer fee_history.deinit();

        try testing.expect(fee_history.response.reward != null);
    }
    {
        const fee_history = try pub_client.feeHistory(5, .{ .block_number = 19062632 }, &[_]f64{ 20, 30 });
        defer fee_history.deinit();

        try testing.expect(fee_history.response.reward != null);
    }
}

test "GetProof" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const proof_result = try pub_client.getProof(.{
            .address = try utils.addressToBytes("0x7F0d15C7FAae65896648C8273B6d7E43f58Fa842"),
            .storageKeys = &.{try utils.hashToBytes("0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")},
        }, .latest);
        defer proof_result.deinit();

        try testing.expect(proof_result.response.accountProof.len != 0);
    }
    {
        const proof_result = try pub_client.getProof(.{
            .address = try utils.addressToBytes("0x7F0d15C7FAae65896648C8273B6d7E43f58Fa842"),
            .storageKeys = &.{try utils.hashToBytes("0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")},
            .blockNumber = 19062632,
        }, null);
        defer proof_result.deinit();

        try testing.expect(proof_result.response.accountProof.len != 0);
    }
}

test "GetBlockByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const slice = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8";
    const block_info = try pub_client.getBlockByHash(.{ .block_hash = try utils.hashToBytes(slice) });
    defer block_info.deinit();

    try testing.expect(block_info.response == .beacon);
    try testing.expectEqual(block_info.response.beacon.number.?, 19062632);
}

test "GetBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const slice = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8";
    const block_info = try pub_client.getBlockTransactionCountByHash(try utils.hashToBytes(slice));
    defer block_info.deinit();

    try testing.expect(block_info.response != 0);
}

test "getBlockTransactionCountByNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const block_info = try pub_client.getBlockTransactionCountByNumber(.{});
        defer block_info.deinit();

        try testing.expect(block_info.response != 0);
    }
    {
        const block_info = try pub_client.getBlockTransactionCountByNumber(.{ .block_number = 19062632 });
        defer block_info.deinit();

        try testing.expect(block_info.response != 0);
    }
}

test "getBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const slice = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8";
    const block_info = try pub_client.getBlockTransactionCountByHash(try utils.hashToBytes(slice));
    defer block_info.deinit();

    try testing.expect(block_info.response != 0);
}

test "getAccounts" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const accounts = try pub_client.getAccounts();
    defer accounts.deinit();

    try testing.expect(accounts.response.len != 0);
}

test "gasPrice" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const gasPrice = try pub_client.getGasPrice();
    defer gasPrice.deinit();

    try testing.expect(gasPrice.response != 0);
}

test "getCode" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const code = try pub_client.getContractCode(.{ .address = try utils.addressToBytes("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2") });
    defer code.deinit();

    const contract_code = "6060604052600436106100af576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306fdde03146100b9578063095ea7b31461014757806318160ddd146101a157806323b872dd146101ca5780632e1a7d4d14610243578063313ce5671461026657806370a082311461029557806395d89b41146102e2578063a9059cbb14610370578063d0e30db0146103ca578063dd62ed3e146103d4575b6100b7610440565b005b34156100c457600080fd5b6100cc6104dd565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561010c5780820151818401526020810190506100f1565b50505050905090810190601f1680156101395780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561015257600080fd5b610187600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061057b565b604051808215151515815260200191505060405180910390f35b34156101ac57600080fd5b6101b461066d565b6040518082815260200191505060405180910390f35b34156101d557600080fd5b610229600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061068c565b604051808215151515815260200191505060405180910390f35b341561024e57600080fd5b61026460048080359060200190919050506109d9565b005b341561027157600080fd5b610279610b05565b604051808260ff1660ff16815260200191505060405180910390f35b34156102a057600080fd5b6102cc600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610b18565b6040518082815260200191505060405180910390f35b34156102ed57600080fd5b6102f5610b30565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561033557808201518184015260208101905061031a565b50505050905090810190601f1680156103625780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561037b57600080fd5b6103b0600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091908035906020019091905050610bce565b604051808215151515815260200191505060405180910390f35b6103d2610440565b005b34156103df57600080fd5b61042a600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610be3565b6040518082815260200191505060405180910390f35b34600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055503373ffffffffffffffffffffffffffffffffffffffff167fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c346040518082815260200191505060405180910390a2565b60008054600181600116156101000203166002900480601f0160208091040260200160405190810160405280929190818152602001828054600181600116156101000203166002900480156105735780601f1061054857610100808354040283529160200191610573565b820191906000526020600020905b81548152906001019060200180831161055657829003601f168201915b505050505081565b600081600460003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b60003073ffffffffffffffffffffffffffffffffffffffff1631905090565b600081600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054101515156106dc57600080fd5b3373ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16141580156107b457507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205414155b156108cf5781600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020541015151561084457600080fd5b81600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055505b81600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000828254039250508190555081600360008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a3600190509392505050565b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410151515610a2757600080fd5b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055503373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501515610ab457600080fd5b3373ffffffffffffffffffffffffffffffffffffffff167f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65826040518082815260200191505060405180910390a250565b600260009054906101000a900460ff1681565b60036020528060005260406000206000915090505481565b60018054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610bc65780601f10610b9b57610100808354040283529160200191610bc6565b820191906000526020600020905b815481529060010190602001808311610ba957829003601f168201915b505050505081565b6000610bdb33848461068c565b905092915050565b60046020528160005260406000206020528060005260406000206000915091505054815600a165627a7a72305820deb4c2ccab3c2fdca32ab3f46728389c2fe2c165d5fafa07661e4e004f6c344a0029";

    var buffer: [contract_code.len / 2]u8 = undefined;
    const bytes = try std.fmt.hexToBytes(&buffer, contract_code);

    try testing.expectEqualSlices(u8, code.response, bytes);
}

test "getAddressBalance" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const address = try pub_client.getAddressBalance(.{ .address = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") });
    defer address.deinit();

    try testing.expectEqual(address.response, try utils.parseEth(10000));
}

test "getUncleCountByBlockHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const uncle = try pub_client.getUncleCountByBlockHash(try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
    defer uncle.deinit();

    try testing.expectEqual(uncle.response, 0);
}

test "getUncleCountByBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const uncle = try pub_client.getUncleCountByBlockNumber(.{});
    defer uncle.deinit();

    try testing.expectEqual(uncle.response, 0);
}

test "getLogs" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const logs = try pub_client.getLogs(.{ .fromBlock = 19062632 }, null);
        defer logs.deinit();

        try testing.expect(logs.response.len == 0);
    }
    {
        const logs = try pub_client.getLogs(.{}, .latest);
        defer logs.deinit();

        try testing.expect(logs.response.len == 0);
    }
    {
        const logs = try pub_client.getLogs(.{ .blockHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8") }, null);
        defer logs.deinit();

        try testing.expect(logs.response.len != 0);
    }
}

test "getStorage" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    {
        const storage = try pub_client.getStorage(
            try utils.addressToBytes("0x295a70b2de5e3953354a6a8344e616ed314d7251"),
            try utils.hashToBytes("0x6661e9d6d8b923d5bbaab1b96e1dd51ff6ea2a93520fdc9eb75d059238b8c5e9"),
            .{ .block_number = 6662363 },
        );
        defer storage.deinit();

        try testing.expectEqualSlices(u8, &try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000000"), &storage.response);
    }
    {
        const storage = try pub_client.getStorage(
            try utils.addressToBytes("0x295a70b2de5e3953354a6a8344e616ed314d7251"),
            try utils.hashToBytes("0x6661e9d6d8b923d5bbaab1b96e1dd51ff6ea2a93520fdc9eb75d059238b8c5e9"),
            .{},
        );
        defer storage.deinit();

        try testing.expectEqualSlices(u8, &try utils.hashToBytes("0x0000000000000000000000000000000000000000000000000000000000000000"), &storage.response);
    }
}

test "getTransactionByBlockNumberAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const tx = try pub_client.getTransactionByBlockNumberAndIndex(.{ .block_number = 16777213 }, 0);
    defer tx.deinit();

    try testing.expect(tx.response == .london);
}

test "getTransactionByBlockHashAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const tx = try pub_client.getTransactionByBlockHashAndIndex(try utils.hashToBytes("0x48f523d98b66742a258dedce6fe47b26867623e190a02c05d450e3f872b4ba49"), 0);
    defer tx.deinit();

    try testing.expect(tx.response == .london);
}

test "getAddressTransactionCount" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const nonce = try pub_client.getAddressTransactionCount(.{ .address = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") });
    defer nonce.deinit();

    try testing.expectEqual(nonce.response, 605);
}

test "getTransactionByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const eip1559 = try pub_client.getTransactionByHash(try utils.hashToBytes("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5"));
    defer eip1559.deinit();

    try testing.expect(eip1559.response == .london);

    // Remove because they fail on CI run.
    // const legacy = try pub_client.getTransactionByHash("0xf9ffe354d26160616844278c4fcbfe0eaa5589da48bc1359eda81fc1ce18b51a");
    // try testing.expect(legacy == .legacy);
    //
    // const tx_untyped = try pub_client.getTransactionByHash("0x0bad3271acf0f10e56caf39187c956583710e1295ee3369a442beda0a666b27a");
    // try testing.expect(tx_untyped == .untyped);
}

test "getTransactionReceipt" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const receipt = try pub_client.getTransactionReceipt(try utils.hashToBytes("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5"));
    defer receipt.deinit();

    try testing.expect(receipt.response.legacy.status != null);

    // Pre-Byzantium
    const legacy = try pub_client.getTransactionReceipt(try utils.hashToBytes("0x4dadc87da2b7c47125fb7e4102d95457830e44d2fbcd45537d91f8be1e5f6130"));
    defer legacy.deinit();

    try testing.expect(legacy.response.legacy.root != null);
}

test "estimateGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const gas = try pub_client.estimateGas(.{ .london = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .value = try utils.parseEth(1) } }, .{});
    defer gas.deinit();

    try testing.expect(gas.response != 0);
}

test "estimateFeesPerGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const gas = try pub_client.estimateFeesPerGas(.{ .london = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .value = try utils.parseEth(1) } }, null);

    try testing.expect(gas.london.max_fee_gas != 0);
    try testing.expect(gas.london.max_priority_fee != 0);
}

test "estimateMaxFeePerGasManual" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    const gas = try pub_client.estimateMaxFeePerGasManual(null);
    try testing.expect(gas != 0);
}

test "Errors" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var pub_client: PubClient = undefined;
    defer pub_client.deinit();

    try pub_client.init(.{ .allocator = testing.allocator, .uri = uri });

    try testing.expectError(error.InvalidBlockHash, pub_client.getBlockByHash(.{ .block_hash = [_]u8{0} ** 32 }));
    try testing.expectError(error.InvalidBlockNumber, pub_client.getBlockByNumber(.{ .block_number = 6969696969696969 }));
    try testing.expectError(error.TransactionReceiptNotFound, pub_client.getTransactionReceipt([_]u8{0} ** 32));
    try testing.expectError(error.TransactionNotFound, pub_client.getTransactionByHash([_]u8{0} ** 32));
    {
        const request =
            \\{"method":"eth_blockNumber","params":["0x6C22BF5",false],"id":1,"jsonrpc":"2.0"}
        ;
        try testing.expectError(error.InvalidParams, pub_client.sendRpcRequest(Gwei, request));
    }
    {
        const request =
            \\{"method":"eth_foo","params":["0x6C22BF5",false],"id":1,"jsonrpc":"2.0"}
        ;
        try testing.expectError(error.MethodNotFound, pub_client.sendRpcRequest(Gwei, request));
    }
    {
        const request =
            \\{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"1.0"}
        ;
        try testing.expectError(error.InvalidRequest, pub_client.sendRpcRequest(Gwei, request));
    }
    {
        const request =
            \\{"method":"eth_sendRawTransaction","params":["0x02f8a00182025d84aa5781ed85042135a28a82fcb88080b846608060405260358060116000396000f3006080604052600080fd00a165627a7a72305820f86ff341f0dff29df244305f8aa88abaf10e3a0719fa6ea1dcdd01b8b7d750970029c080a0450d28b8b3e1d5bd0bf99140ffb60059fc55c5ed184a62bf7e46a93f0a733553a012bfec695102b9ef50d21e607bdd01d4dbbd3e50461d9d43451fea330bf299a8"],"id":1,"jsonrpc":"2.0"}
        ;
        try testing.expectError(error.TransactionRejected, pub_client.sendRpcRequest(Gwei, request));
    }
    {
        // Not supported on all RPC providers :/
        try testing.expectError(error.MethodNotFound, pub_client.blobBaseFee());
        try testing.expectError(error.MethodNotFound, pub_client.estimateBlobMaxFeePerGas());
    }
    {
        const request =
            \\{"jsonrpc":"2.0","method":"eth_call","params": [{"from": "0x49989f8c3F9Ba9260DEc65272dD411c8F8c8ec4A","to": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "gas": "0xe324343242", "data":"0xa9059cbb00000000000000000000000099870de8ae594e6e8705fc6689e89b4d039af1e2000000000000000000000000000000000000000000000000000000181d2963cb3a940c0cf4f61682f62abd4c30e374369ba8fc88fcaf47fc79c46122732f19d0"}, "latest"],"id":1} 
        ;
        try testing.expectError(error.EvmFailedToExecute, pub_client.sendRpcRequest(Hex, request));
    }
}
