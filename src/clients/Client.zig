const block = @import("../types/block.zig");
const decoder = @import("../decoding/decoder.zig");
const http = std.http;
const log = @import("../types/log.zig");
const network = @import("network.zig");
const meta = @import("../meta/utils.zig");
const meta_abi = @import("../meta/abi.zig");
const multicall = @import("multicall.zig");
const proof = @import("../types/proof.zig");
const std = @import("std");
const sync = @import("../types/syncing.zig");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");
const txpool = @import("../types/txpool.zig");

// Types
const AbiDecoded = decoder.AbiDecoded;
const AbiParametersToPrimative = meta_abi.AbiParametersToPrimative;
const AccessListResult = transaction.AccessListResult;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const BalanceBlockTag = block.BalanceBlockTag;
const BalanceRequest = block.BalanceRequest;
const Block = block.Block;
const BlockHashRequest = block.BlockHashRequest;
const BlockNumberRequest = block.BlockNumberRequest;
const BlockRequest = block.BlockRequest;
const BlockTag = block.BlockTag;
const Call3 = multicall.Call3;
const Chains = types.PublicChains;
const EthCall = transaction.EthCall;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
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
const Multicall = multicall.Multicall;
const MulticallArguments = multicall.MulticallArguments;
const MulticallTargets = multicall.MulticallTargets;
const NetworkConfig = network.NetworkConfig;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const Result = multicall.Result;
const RPCResponse = types.RPCResponse;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const TxPoolContent = txpool.TxPoolContent;
const TxPoolInspect = txpool.TxPoolInspect;
const TxPoolStatus = txpool.TxPoolStatus;
const Tuple = std.meta.Tuple;
const Uri = std.Uri;
const Wei = types.Wei;

const httplog = std.log.scoped(.http);

pub const HttpClientError = error{
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
} || Allocator.Error || std.fmt.ParseIntError || http.Client.RequestError || std.Uri.ParseError;

const protocol_map = std.StaticStringMap(HttpConnection.Protocol).initComptime(.{
    .{ "http", .plain },
    .{ "ws", .plain },
    .{ "https", .tls },
    .{ "wss", .tls },
});

/// Init options for defining the initial state of the http/s client.
///
/// Consider using the network options defined [here](/api/clients/network#ethereum_mainnet) if you need a default network config.
pub const InitOptions = struct {
    /// Allocator used to manage the memory arena.
    allocator: Allocator,
    /// The network config for the client to use.
    network_config: NetworkConfig,
};

/// This allocator will get set by the arena.
allocator: Allocator,
/// The underlaying http client used to manage all the calls.
client: http.Client,
/// Connection used as a reference for http client connections
connection: *HttpConnection,
/// The network config that the client is connected to.
network_config: NetworkConfig,

const PubClient = @This();

/// Sets the clients initial state. This is the HTTP/S implementation of the JSON RPC client.
///
/// Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.
///
/// The client will handle request with 429 errors via exponential backoff
/// but not the rest of the http error codes.
///
/// **Example:**
/// ```zig
/// const std = @import("std");
/// const zabi = @import("zabi");
///
/// const RpcClient = zabi.clients.PubClient;
///
/// const allocator = std.heap.page_allocator;
/// const uri = std.Uri.parse("http://localhost:8545/");
///
/// var client = try RpcClient.init(.{
///     .network_config = .{.endpoint = .{.uri = uri }, .chain_id = .ethereum, },
///     .allocator = allocator,
/// })
/// defer client.deinit();
/// ```
pub fn init(opts: InitOptions) !*PubClient {
    const self = try opts.allocator.create(PubClient);
    errdefer opts.allocator.destroy(self);

    if (opts.network_config.endpoint != .uri)
        return error.InvalidPathConfigOption;

    self.* = .{
        .allocator = opts.allocator,
        .client = http.Client{ .allocator = opts.allocator },
        .connection = undefined,
        .network_config = opts.network_config,
    };
    errdefer self.client.deinit();

    self.connection = try self.connectRpcServer();

    return self;
}
/// Clears all allocated memory and destroys any created pointers.
pub fn deinit(self: *PubClient) void {
    std.debug.assert(self.network_config.endpoint == .uri); // Invalid config.

    // We have a lingering connection so we close it and destroy it
    if (self.client.connection_pool.used.first != null) {
        self.client.connection_pool.used.first = null;
        const scheme = protocol_map.get(self.network_config.endpoint.uri.scheme) orelse {
            self.client = undefined;
            return;
        };

        if (scheme == .tls) {
            self.client.ca_bundle.deinit(self.client.allocator);
        }

        self.client = undefined;

        const allocator = self.allocator;
        allocator.destroy(self);

        return;
    }

    self.client.deinit();

    const allocator = self.allocator;
    allocator.destroy(self);
}
/// Connects to the target JSON-RPC endpoint.
///
/// In case of failure this will retry the connect by the amount of times defined in the `network_config`.\
/// This also increments the waiting period by the `pooling_interval` set in the initial config.
pub fn connectRpcServer(self: *PubClient) !*HttpConnection {
    const uri = self.network_config.getNetworkUri() orelse return error.InvalidEndpointConfig;

    const scheme = protocol_map.get(uri.scheme) orelse return error.UnsupportedSchema;
    const port: u16 = uri.port orelse switch (scheme) {
        .plain => 80,
        .tls => 443,
    };

    var retries: usize = 0;
    const connection = while (true) : (retries += 1) {
        if (retries > self.network_config.retries)
            return error.FailedToConnect;

        switch (retries) {
            0...2 => {},
            else => {
                const sleep_timing: u64 = @min(10_000, self.network_config.pooling_interval * retries);
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

        const hostname = switch (uri.host.?) {
            .raw => |raw| raw,
            .percent_encoded => |host| host,
        };

        const connection = self.client.connect(hostname, port, scheme) catch |err| {
            httplog.debug("Connection failed: {s}", .{@errorName(err)});
            continue;
        };

        break connection;
    };

    self.client.connection_pool.release(self.allocator, connection);

    return connection;
}
/// Grabs the current base blob fee. Make sure that your endpoint supports `eth_blobBaseFee`
///
/// RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)
pub fn blobBaseFee(self: *PubClient) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_blobBaseFee);
}
/// Create an accessList of addresses and storageKeys for an transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
///
/// **Example:**
/// ```zig
/// const std = @import("std");
/// const zabi = @import("zabi");
///
/// const RpcClient = zabi.clients.PubClient;
///
/// const allocator = std.heap.page_allocator;
/// const uri = std.Uri.parse("http://localhost:8545/");
///
/// var client = try RpcClient.init(.{
///     .network_config = .{.endpoint = .{.uri = uri }, .chain_id = .ethereum, },
///     .allocator = allocator,
/// })
/// defer client.deinit();
///
/// const access = try client.createAccessList(.{ .london = .{ .value = 10 } }, .{});
/// defer access.deinit();
/// ```
pub fn createAccessList(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}
/// Estimate the gas used for blobs.
///
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation.
pub fn estimateBlobMaxFeePerGas(self: *PubClient) !Gwei {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else gas_price.response - base.response;
}
/// Estimate `maxPriorityFeePerGas` and `maxFeePerGas` for london enabled chains and `gasPrice` if not.\
/// This method will make multiple http requests in order to calculate this.
///
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
///
/// Will return an error in case the `baseFeePerGas` is null.
///
/// **Example:**
/// ```zig
/// const std = @import("std");
/// const zabi = @import("zabi");
///
/// const RpcClient = zabi.clients.PubClient;
///
/// const allocator = std.heap.page_allocator;
/// const uri = std.Uri.parse("http://localhost:8545/");
///
/// var client = try RpcClient.init(.{
///     .network_config = .{.endpoint = .{.uri = uri }, .chain_id = .ethereum, },
///     .allocator = allocator,
/// })
/// defer client.deinit();
///
/// const fees = try client.estimateFeesPerGas(.{ .london = .{ .value = 10 } }, null);
/// defer fees.deinit();
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

            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(base_fee)) * self.network_config.base_fee_multiplier);
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
            const mutiplier = std.math.ceil(@as(f64, @floatFromInt(gas_price)) * self.network_config.base_fee_multiplier);
            const price: u64 = @intFromFloat(mutiplier);
            return .{
                .legacy = .{ .gas_price = price },
            };
        },
    }
}
/// Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
///
/// The transaction will not be added to the blockchain.
///
/// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
/// for a variety of reasons including EVM mechanics and node performance.
///
/// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
///
/// **Example:**
/// ```zig
/// const std = @import("std");
/// const zabi = @import("zabi");
///
/// const RpcClient = zabi.clients.PubClient;
///
/// const allocator = std.heap.page_allocator;
/// const uri = std.Uri.parse("http://localhost:8545/");
///
/// var client = try RpcClient.init(.{
///     .network_config = .{.endpoint = .{.uri = uri }, .chain_id = .ethereum, },
///     .allocator = allocator,
/// })
/// defer client.deinit();
///
/// const gas = try client.estimateGas(.{ .london = .{ .value = 10 } }, .{});
/// defer gas.deinit();
pub fn estimateGas(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
    return self.sendEthCallRequest(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates `maxPriorityFeePerGas` manually.
///
/// Gets the information based on the latest block if `base_fee_per_gas` is set to null.
///
/// If the node you are currently using supports `eth_maxPriorityFeePerGas` consider using [estimateMaxFeePerGas](/api/clients/Client#estimateMaxFeePerGas).
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
    return self.sendBasicRequest(Gwei, .eth_maxPriorityFeePerGas);
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
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { u64, BalanceBlockTag, ?[]const f64 }) = .{
            .params = .{ blockCount, tag, reward_percentil },
            .method = .eth_feeHistory,
            .id = @intFromEnum(self.network_config.chain_id),
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
    return self.getBlockByHashType(Block, opts);
}
/// Returns information about a block by hash.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHashType(self: *PubClient, comptime T: type, opts: BlockHashRequest) !RPCResponse(T) {
    const include = opts.include_transaction_objects orelse false;

    const request: EthereumRequest(struct { Hash, bool }) = .{
        .params = .{ opts.block_hash, include },
        .method = .eth_getBlockByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const request_block = try self.sendRpcRequest(?T, buf_writter.getWritten());
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
    return self.getBlockByNumberType(Block, opts);
}
/// Returns information about a block by number.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumberType(self: *PubClient, comptime T: type, opts: BlockRequest) !RPCResponse(T) {
    const tag: BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, bool }) = .{
            .params = .{ number, include },
            .method = .eth_getBlockByNumber,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BlockTag, bool }) = .{
            .params = .{ tag, include },
            .method = .eth_getBlockByNumber,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const request_block = try self.sendRpcRequest(?T, buf_writter.getWritten());
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
    return self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *PubClient, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *PubClient) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_chainId);
}
/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *PubClient) !RPCResponse([]const u8) {
    return self.sendBasicRequest([]const u8, .web3_clientVersion);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *PubClient, opts: BalanceRequest) !RPCResponse(Hex) {
    return self.sendAddressRequest(Hex, opts, .eth_getCode);
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// returns an array of all logs matching filter with given id depending on the selected method
///
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges \
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *PubClient, filter_id: u128, method: EthereumRpcMethods) !RPCResponse(Logs) {
    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    switch (method) {
        .eth_getFilterLogs, .eth_getFilterChanges => {},
        else => return error.InvalidRpcMethod,
    }

    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{filter_id},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_filter = try self.sendRpcRequest(?Logs, buf_writter.getWritten());
    const filter = possible_filter.response orelse return error.InvalidFilterId;

    return .{
        .arena = possible_filter.arena,
        .response = filter,
    };
}
/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *PubClient) !RPCResponse(Gwei) {
    return self.sendBasicRequest(u64, .eth_gasPrice);
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
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_getLogs,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    const possible_logs = try self.sendRpcRequest(?Logs, buf_writter.getWritten());
    errdefer possible_logs.deinit();

    const logs = possible_logs.response orelse return error.InvalidLogRequestParams;

    return .{
        .arena = possible_logs.arena,
        .response = logs,
    };
}
/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *PubClient) !RPCResponse(bool) {
    return self.sendBasicRequest(bool, .net_listening);
}
/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *PubClient) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_peerCount);
}
/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *PubClient) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_version);
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
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const number = opts.blockNumber orelse return error.ExpectBlockNumberOrTag;

        const request: EthereumRequest(struct { Address, []const Hash, u64 }) = .{
            .params = .{ opts.address, opts.storageKeys, number },
            .method = .eth_getProof,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(ProofResult, buf_writter.getWritten());
}
/// Returns the current Ethereum protocol version.
///
/// RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)
pub fn getProtocolVersion(self: *PubClient) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_protocolVersion);
}
/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(self: *PubClient, tx_hash: Hash) !RPCResponse(Hex) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{tx_hash},
        .method = .eth_getRawTransactionByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hex, buf_writter.getWritten());
}
/// Returns the Keccak256 hash of the given message.
/// This converts the message into to hex values.
///
/// RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)
pub fn getSha3Hash(self: *PubClient, message: []const u8) !RPCResponse(Hash) {
    const message_hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(message)});
    defer self.allocator.free(message_hex);

    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{message_hex},
        .method = .web3_sha3,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [4096]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
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
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, Hash, BalanceBlockTag }) = .{
            .params = .{ address, storage_key, tag },
            .method = .eth_getStorageAt,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
}
/// Returns null if the node has finished syncing. Otherwise it will return
/// the sync progress.
///
/// RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)
pub fn getSyncStatus(self: *PubClient) !?RPCResponse(SyncProgress) {
    return self.sendBasicRequest(SyncProgress, .eth_syncing) catch null;
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Transaction) {
    return self.getTransactionByBlockHashAndIndexType(Transaction, block_hash, index);
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndexType(self: *PubClient, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getTransactionByBlockHashAndIndex,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_tx = try self.sendRpcRequest(?T, buf_writter.getWritten());
    errdefer possible_tx.deinit();

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}
pub fn getTransactionByBlockNumberAndIndex(self: *PubClient, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction) {
    return self.getTransactionByBlockNumberAndIndexType(Transaction, opts, index);
}
/// Returns information about a transaction by block number and transaction index position.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndexType(self: *PubClient, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getTransactionByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const possible_tx = try self.sendRpcRequest(?T, buf_writter.getWritten());
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
    return self.getTransactionByHashType(Transaction, transaction_hash);
}
/// Returns the information about a transaction requested by transaction hash.
///
/// Consider using this method if the provided `Transaction` types fail to json parse the request and
/// you know extractly the shape of the data that the transaction is expected to be like.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHashType(self: *PubClient, comptime T: type, transaction_hash: Hash) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionByHash,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_tx = try self.sendRpcRequest(?T, buf_writter.getWritten());
    errdefer possible_tx.deinit();

    const tx = possible_tx.response orelse return error.TransactionNotFound;

    return .{
        .arena = possible_tx.arena,
        .response = tx,
    };
}
/// Returns the receipt of a transaction by transaction hash.
///
/// Consider using this method if the provided `TransactionReceipt` types fail to json parse the request and
/// you know extractly the shape of the data that the receipt is expected to be like.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(self: *PubClient, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
    return self.getTransactionReceiptType(TransactionReceipt, transaction_hash);
}
/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceiptType(self: *PubClient, comptime T: type, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionReceipt,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const possible_receipt = try self.sendRpcRequest(?T, buf_writter.getWritten());
    errdefer possible_receipt.deinit();

    const receipt = possible_receipt.response orelse return error.TransactionReceiptNotFound;

    return .{
        .arena = possible_receipt.arena,
        .response = receipt,
    };
}
/// The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// The result is an object with two fields pending and queued.\
/// Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.\
/// These batches themselves are maps associating nonces with actual transactions.
///
/// RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContent(self: *PubClient) !RPCResponse(TxPoolContent) {
    return self.sendBasicRequest(TxPoolContent, .txpool_content);
}
/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(self: *PubClient, from: Address) !RPCResponse([]const PoolTransactionByNonce) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{from},
        .method = .txpool_contentFrom,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    return self.sendRpcRequest([]const PoolTransactionByNonce, buf_writter.getWritten());
}
/// The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.\
/// This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.
///
/// RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolInspectStatus(self: *PubClient) !RPCResponse(TxPoolInspect) {
    return self.sendBasicRequest(TxPoolInspect, .txpool_inspect);
}
/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *PubClient) !RPCResponse(TxPoolStatus) {
    return self.sendBasicRequest(TxPoolStatus, .txpool_status);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *PubClient, block_hash: Hash, index: usize) !RPCResponse(Block) {
    return self.getUncleByBlockHashAndIndexType(Block, block_hash, index);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndexType(self: *PubClient, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getUncleByBlockHashAndIndex,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    const request_block = try self.sendRpcRequest(?T, buf_writter.getWritten());
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
    return self.getUncleByBlockNumberAndIndexType(Block, opts, index);
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// Consider using this method if the provided `Block` types fail to json parse the request and
/// you know extractly the shape of the data that the block is expected to be like.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndexType(self: *PubClient, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    const request_block = try self.sendRpcRequest(?T, buf_writter.getWritten());
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
/// Runs the selected multicall3 contracts.
///
/// This enables to read from multiple contract by a single `eth_call`.\
/// Uses the contracts created [here](https://www.multicall3.com/)
///
/// To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)
///
/// You will need to decoded each of the `Result`.
///
/// **Example:**
/// ```zig
///  const supply: Function = .{
///       .type = .function,
///       .name = "totalSupply",
///       .stateMutability = .view,
///       .inputs = &.{},
///       .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
///   };
///
///   const balance: Function = .{
///       .type = .function,
///       .name = "balanceOf",
///       .stateMutability = .view,
///       .inputs = &.{.{ .type = .{ .address = {} }, .name = "balanceOf" }},
///       .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
///   };
///
///   const a: []const MulticallTargets = &.{
///       .{ .function = supply, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
///       .{ .function = balance, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
///   };
///
///   const res = try client.multicall3(a, .{ {}, .{try utils.addressToBytes("0xFded38DF0180039867E54EBdec2012D534862cE3")} }, true);
///   defer res.deinit();
/// ```
pub fn multicall3(
    self: *PubClient,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) !AbiDecoded([]const Result) {
    var multicall_caller = try Multicall(.http).init(self);

    return multicall_caller.multicall3(targets, function_arguments, allow_failure);
}
/// Creates a filter in the node, to notify when a new block arrives.
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *PubClient) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *PubClient, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128) {
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
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_newFilter,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
///
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *PubClient) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newPendingTransactionFilter);
}
/// Executes a new message call immediately without creating a transaction on the block chain.\
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *PubClient, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Hex) {
    return self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *PubClient, serialized_tx: Hex) !RPCResponse(Hash) {
    const request: EthereumRequest(struct { Hex }) = .{
        .params = .{serialized_tx},
        .method = .eth_sendRawTransaction,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
}
/// Waits until a transaction gets mined and the receipt can be grabbed.\
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(self: *PubClient, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
    return self.waitForTransactionReceiptType(TransactionReceipt, tx_hash, confirmations);
}
/// Waits until a transaction gets mined and the receipt can be grabbed.\
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// Consider using this method if the provided `TransactionReceipt` types fail to json parse the request and
/// you know extractly the shape of the data that the receipt is expected to be like.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceiptType(self: *PubClient, comptime T: type, tx_hash: Hash, confirmations: u8) !RPCResponse(T) {
    var tx: ?RPCResponse(Transaction) = null;
    defer if (tx) |tx_res| tx_res.deinit();

    const block_number_request = try self.getBlockNumber();
    defer block_number_request.deinit();

    var block_number = block_number_request.response;

    var receipt: ?RPCResponse(T) = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
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
        if (retries - valid_confirmations > self.network_config.retries)
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
                std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                continue;
            }
        }

        if (tx == null) {
            tx = self.getTransactionByHash(tx_hash) catch |err| switch (err) {
                // If it fails we keep trying
                error.TransactionNotFound => {
                    std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
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
                        std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
                        continue;
                    },
                };

                const pending_transaction = switch (block_transactions) {
                    .hashes => {
                        std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
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

                std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
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
            std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
            continue;
        }
    }

    return if (receipt) |tx_receipt| tx_receipt else error.FailedToGetReceipt;
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
///
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstallFilter(self: *PubClient, id: usize) !RPCResponse(bool) {
    const request: EthereumRequest(struct { usize }) = .{
        .params = .{id},
        .method = .eth_uninstallFilter,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(bool, buf_writter.getWritten());
}
/// Writes request to RPC server and parses the response according to the provided type.
/// Handles 429 errors but not the rest.
pub fn sendRpcRequest(self: *PubClient, comptime T: type, request: []const u8) !RPCResponse(T) {
    httplog.debug("Preparing to send request body: {s}", .{request});

    var body = std.ArrayList(u8).init(self.allocator);
    defer body.deinit();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.network_config.retries)
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
                const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                httplog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                // Clears any message that was written
                try body.resize(0);

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => {
                httplog.debug("Unexpected server response. Server returned: {s} status", .{req.status.phrase() orelse @tagName(req.status)});
                return error.UnexpectedServerResponse;
            },
        }
    }
}
// Sends specific block_number requests.
fn sendBlockNumberRequest(self: *PubClient, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(usize) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64 }) = .{
            .params = .{number},
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag }) = .{
            .params = .{tag},
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(usize, buf_writter.getWritten());
}
// Sends specific block_hash requests.
fn sendBlockHashRequest(self: *PubClient, block_hash: Hash, method: EthereumRpcMethods) !RPCResponse(usize) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{block_hash},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(usize, buf_writter.getWritten());
}
// Sends request specific for addresses.
fn sendAddressRequest(self: *PubClient, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    return self.sendRpcRequest(T, buf_writter.getWritten());
}
// Sends requests where the params are empty.
fn sendBasicRequest(self: *PubClient, comptime T: type, method: EthereumRpcMethods) !RPCResponse(T) {
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = method,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(T, buf_writter.getWritten());
}
// Sends eth_call request
fn sendEthCallRequest(self: *PubClient, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = method,
            .id = @intFromEnum(self.network_config.chain_id),
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    return self.sendRpcRequest(T, buf_writter.getWritten());
}
/// Internal PubClient fetch. Optimized for our use case.
fn internalFetch(self: *PubClient, payload: []const u8, body: *std.ArrayList(u8)) !FetchResult {
    var server_header_buffer: [16 * 1024]u8 = undefined;
    const uri = self.network_config.getNetworkUri() orelse return error.InvalidEndpointConfig;

    var request = try self.client.open(.POST, uri, .{
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

    try request.send();

    try request.writeAll(payload);

    try request.finish();
    try request.wait();

    const max_size = 5 * 1024 * 1024;
    try request.reader().readAllArrayList(body, max_size);

    return .{
        .status = request.response.status,
    };
}

fn parseRPCEvent(self: *PubClient, comptime T: type, request: []const u8) !RPCResponse(T) {
    const parsed = std.json.parseFromSlice(
        EthereumResponse(T),
        self.allocator,
        request,
        .{ .allocate = .alloc_always },
    ) catch return error.UnexpectedErrorFound;

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
                .UserRejectedRequest => return error.UserRejectedRequest,
                .Unauthorized => return error.Unauthorized,
                .UnsupportedMethod => return error.UnsupportedMethod,
                .Disconnected => return error.Disconnected,
                .ChainDisconnected => return error.ChainDisconnected,
                _ => return error.UnexpectedRpcErrorCode,
            }
        },
    }
}
