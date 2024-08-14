const abi = @import("../abi/abi.zig");
const block = @import("../types/block.zig");
const decoder = @import("../decoding/decoder.zig");
const meta = @import("../meta/utils.zig");
const multicall = @import("multicall.zig");
const log = @import("../types/log.zig");
const pipe = @import("../utils/pipe.zig");
const proof = @import("../types/proof.zig");
const std = @import("std");
const sync = @import("../types/syncing.zig");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");
const txpool = @import("../types/txpool.zig");
const utils = @import("../utils/utils.zig");
const ws = @import("ws");

const AbiDecoded = decoder.AbiDecoded;
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
const Chains = types.PublicChains;
const Channel = @import("../utils/channel.zig").Channel;
const EthCall = transaction.EthCall;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EthereumRpcResponse = types.EthereumRpcResponse;
const EthereumSubscribeResponse = types.EthereumSubscribeResponse;
const EthereumZigErrors = types.EthereumZigErrors;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
const FeeHistory = transaction.FeeHistory;
const Function = abi.Function;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const JsonParsed = std.json.Parsed;
const Log = log.Log;
const LogRequest = log.LogRequest;
const LogTagRequest = log.LogTagRequest;
const Logs = log.Logs;
const Multicall = multicall.Multicall;
const MulticallArguments = multicall.MulticallArguments;
const MulticallTargets = multicall.MulticallTargets;
const Mutex = std.Thread.Mutex;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const Result = multicall.Result;
const RPCResponse = types.RPCResponse;
const Stack = @import("../utils/stack.zig").Stack;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const Tuple = std.meta.Tuple;
const TxPoolContent = txpool.TxPoolContent;
const TxPoolInspect = txpool.TxPoolInspect;
const TxPoolStatus = txpool.TxPoolStatus;
const Uri = std.Uri;
const Value = std.json.Value;
const WatchLogsRequest = log.WatchLogsRequest;
const Subscriptions = types.Subscriptions;
const Wei = types.Wei;

const WebSocketHandler = @This();

const wslog = std.log.scoped(.ws);

pub const WebSocketHandlerErrors = error{
    FailedToConnect,
    UnsupportedSchema,
    InvalidChainId,
    FailedToGetReceipt,
    FailedToUnsubscribe,
    InvalidFilterId,
    InvalidEventFound,
    InvalidBlockRequest,
    InvalidLogRequest,
    TransactionNotFound,
    TransactionReceiptNotFound,
    InvalidHash,
    UnableToFetchFeeInfoFromBlock,
    InvalidAddress,
    InvalidBlockHash,
    InvalidBlockHashOrIndex,
    InvalidBlockNumberOrIndex,
    InvalidBlockNumber,
    ReachedMaxRetryLimit,
} || InitErrors || std.fmt.ParseIntError || std.Uri.ParseError || EthereumZigErrors;

pub const ConnectionErrors = error{ UnsupportedSchema, FailedToConnect, MissingUrlPath, OutOfMemory, UnspecifiedHostName };
pub const InitErrors = ConnectionErrors || Allocator.Error || std.Thread.SpawnError;

pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The uri of the server to connect to.
    uri: std.Uri,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
    /// Retry count for failed connections to the server.
    retries: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
};

/// The allocator that will manage the connections memory
allocator: Allocator,
/// The base fee multiplier used to estimate the gas fees in a transaction
base_fee_multiplier: f64,
/// The chain id of the attached network
chain_id: usize,
/// Channel used to communicate between threads on subscription events.
sub_channel: Channel(JsonParsed(Value)),
/// Channel used to communicate between threads on rpc events.
rpc_channel: Stack(JsonParsed(Value)),
/// Mutex to manage locks between threads
mutex: Mutex = .{},
/// Callback function for when the connection is closed.
onClose: ?*const fn () void = null,
/// Callback function that will run once a socket event is parsed
onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void,
/// Callback function that will run once a error is parsed.
onError: ?*const fn (args: []const u8) anyerror!void,
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// Retry count for failed connections to the server.
retries: u8,
/// The uri of the connection
uri: std.Uri,
/// The underlaying websocket client
ws_client: ws.Client,

const protocol_map = std.StaticStringMap(std.http.Client.Connection.Protocol).initComptime(.{
    .{ "http", .plain },
    .{ "ws", .plain },
    .{ "https", .tls },
    .{ "wss", .tls },
});

/// This will get run everytime a socket message is found.
/// All messages are parsed and put into the handlers channel.
/// All callbacks will only affect this function.
pub fn handle(self: *WebSocketHandler, message: ws.Message) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    wslog.debug("Got message: {s}", .{message.data});
    switch (message.type) {
        .text => {
            const parsed = self.parseRPCEvent(message.data) catch {
                if (self.onError) |onError| {
                    try onError(message.data);
                }

                return error.FailedToJsonParseResponse;
            };

            if (parsed.value != .object)
                return error.InvalidTypeMessage;

            // You need to check what type of event it is.
            if (self.onEvent) |onEvent| {
                try onEvent(parsed);
            }

            if (parsed.value.object.getKey("params") != null) {
                return self.sub_channel.put(parsed);
            }

            return self.rpc_channel.push(parsed);
        },
        else => {},
    }
}

/// Populates the WebSocketHandler pointer.
/// Starts the connection in a seperate process.
pub fn init(self: *WebSocketHandler, opts: InitOptions) InitErrors!void {
    const chain: Chains = opts.chain_id orelse .ethereum;

    self.* = .{
        .allocator = opts.allocator,
        .base_fee_multiplier = opts.base_fee_multiplier,
        .chain_id = @intFromEnum(chain),
        .onClose = opts.onClose,
        .onError = opts.onError,
        .onEvent = opts.onEvent,
        .pooling_interval = opts.pooling_interval,
        .retries = opts.retries,
        .rpc_channel = Stack(JsonParsed(Value)).init(self.allocator, null),
        .sub_channel = Channel(JsonParsed(Value)).init(self.allocator),
        .uri = opts.uri,
        .ws_client = undefined,
    };

    errdefer {
        self.rpc_channel.deinit();
        self.sub_channel.deinit();
    }

    self.ws_client = try self.connect();

    const thread = try std.Thread.spawn(.{}, readLoopOwned, .{self});
    thread.detach();
}
/// All future interactions will deadlock
/// If you are using the subscription channel this operation can take time
/// as it will need to cleanup each node.
pub fn deinit(self: *WebSocketHandler) void {
    self.mutex.lock();

    while (@atomicRmw(bool, &self.ws_client._closed, .Xchg, true, .seq_cst)) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    // There may be lingering memory from the json parsed data
    // in the channels so we must clean then up.
    while (self.sub_channel.getOrNull()) |node| {
        node.deinit();
    }

    while (self.rpc_channel.popOrNull()) |node| {
        node.deinit();
    }

    // Deinits client and destroys any created pointers.
    self.sub_channel.deinit();
    self.rpc_channel.deinit();
    self.ws_client.deinit();
}
/// Connects to a socket client. This is a blocking operation.
pub fn connect(self: *WebSocketHandler) ConnectionErrors!ws.Client {
    const scheme = protocol_map.get(self.uri.scheme) orelse return error.UnsupportedSchema;
    const port: u16 = self.uri.port orelse switch (scheme) {
        .plain => 80,
        .tls => 443,
    };

    var retries: u8 = 0;
    const client = while (true) : (retries += 1) {
        if (retries > self.retries)
            break error.FailedToConnect;

        switch (retries) {
            0...2 => {},
            else => {
                const sleep_timing: u64 = @min(5_000, self.pooling_interval * retries);
                std.time.sleep(sleep_timing * std.time.ns_per_ms);
            },
        }

        const hostname = switch (self.uri.host orelse return error.UnspecifiedHostName) {
            .raw => |raw| raw,
            .percent_encoded => |host| host,
        };

        var client = ws.connect(self.allocator, hostname, port, .{
            .tls = scheme == .tls,
            .max_size = std.math.maxInt(u32),
            .buffer_size = 10 * std.math.maxInt(u16),
        }) catch |err| {
            wslog.debug("Connection failed: {s}", .{@errorName(err)});
            continue;
        };
        errdefer client.deinit();

        const headers = try std.fmt.allocPrint(self.allocator, "Host: {s}", .{hostname});
        defer self.allocator.free(headers);

        if (self.uri.path.isEmpty())
            return error.MissingUrlPath;

        const path = switch (self.uri.path) {
            .raw => |raw| raw,
            .percent_encoded => |host| host,
        };

        client.handshake(path, .{ .headers = headers, .timeout_ms = 5_000 }) catch |err| {
            wslog.debug("Handshake failed: {s}", .{@errorName(err)});
            continue;
        };

        break client;
    };

    return client;
}
/// Runs the callback once the handler close method gets called by the ws_client
pub fn close(self: *WebSocketHandler) void {
    if (self.onClose) |onClose| {
        return onClose();
    }
}
/// Grabs the current base blob fee.
///
/// RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)
pub fn blobBaseFee(self: *WebSocketHandler) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_blobBaseFee);
}
/// Create an accessList of addresses and storageKeys for an transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}
/// Estimate the gas used for blobs
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation
pub fn estimateBlobMaxFeePerGas(self: *WebSocketHandler) !Gwei {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else gas_price.response - base.response;
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(self: *WebSocketHandler, call_object: EthCall, base_fee_per_gas: ?Gwei) !EstimateFeeReturn {
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
pub fn estimateGas(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
    return self.sendEthCallRequest(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *WebSocketHandler, base_fee_per_gas: ?Gwei) !Gwei {
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
pub fn estimateMaxFeePerGas(self: *WebSocketHandler) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_maxPriorityFeePerGas);
}
/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(self: *WebSocketHandler, blockCount: u64, newest_block: BlockNumberRequest, reward_percentil: ?[]const f64) !RPCResponse(FeeHistory) {
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
pub fn getAccounts(self: *WebSocketHandler) !RPCResponse([]const Address) {
    return self.sendBasicRequest([]const Address, .eth_accounts);
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *WebSocketHandler, opts: BalanceRequest) !RPCResponse(Wei) {
    return self.sendAddressRequest(Wei, opts, .eth_getBalance);
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *WebSocketHandler, opts: BalanceRequest) !RPCResponse(u64) {
    return self.sendAddressRequest(u64, opts, .eth_getTransactionCount);
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(self: *WebSocketHandler, opts: BlockHashRequest) !RPCResponse(Block) {
    return self.getBlockByHashType(Block, opts);
}
/// Returns information about a block by hash.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHashType(self: *WebSocketHandler, comptime T: type, opts: BlockHashRequest) !RPCResponse(T) {
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
pub fn getBlockByNumber(self: *WebSocketHandler, opts: BlockRequest) !RPCResponse(Block) {
    return self.getBlockByNumberType(Block, opts);
}
/// Returns information about a block by number.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)
pub fn getBlockByNumberType(self: *WebSocketHandler, comptime T: type, opts: BlockRequest) !RPCResponse(T) {
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
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockNumber(self: *WebSocketHandler) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blockNumber);
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *WebSocketHandler, block_hash: Hash) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *WebSocketHandler, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *WebSocketHandler) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_chainId);
}
/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *WebSocketHandler) !RPCResponse([]const u8) {
    return self.sendBasicRequest([]const u8, .web3_clientVersion);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *WebSocketHandler, opts: BalanceRequest) !RPCResponse(Hex) {
    return self.sendAddressRequest(Hex, opts, .eth_getCode);
}
/// Get the first event of the rpc channel.
///
/// Only call this if you are sure that the channel has messages
/// because this will block until a message is able to be fetched.
pub fn getCurrentRpcEvent(self: *WebSocketHandler) JsonParsed(Value) {
    return self.rpc_channel.pop();
}
/// Get the first event of the subscription channel.
///
/// Only call this if you are sure that the channel has messages
/// because this will block until a message is able to be fetched.
pub fn getCurrentSubscriptionEvent(self: *WebSocketHandler) JsonParsed(Value) {
    return self.sub_channel.get();
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *WebSocketHandler, filter_id: u128, method: EthereumRpcMethods) !RPCResponse(Logs) {
    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    switch (method) {
        .eth_getFilterLogs, .eth_getFilterChanges => {},
        else => return error.InvalidRpcMethod,
    }

    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{filter_id},
        .method = method,
        .id = self.chain_id,
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
pub fn getGasPrice(self: *WebSocketHandler) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_gasPrice);
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *WebSocketHandler, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(Logs) {
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

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_getLogs,
            .id = self.chain_id,
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
/// Parses the `Value` in the sub-channel as a log event
pub fn getLogsSubEvent(self: *WebSocketHandler) !RPCResponse(EthereumSubscribeResponse(Log)) {
    return self.parseSubscriptionEvent(Log);
}
/// Parses the `Value` in the sub-channel as a new heads block event
pub fn getNewHeadsBlockSubEvent(self: *WebSocketHandler) !RPCResponse(EthereumSubscribeResponse(Block)) {
    return self.parseSubscriptionEvent(Block);
}
/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *WebSocketHandler) !RPCResponse(bool) {
    return self.sendBasicRequest(bool, .net_listening);
}
/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *WebSocketHandler) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_peerCount);
}
/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *WebSocketHandler) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_version);
}
/// Parses the `Value` in the sub-channel as a pending transaction hash event
pub fn getPendingTransactionsSubEvent(self: *WebSocketHandler) !RPCResponse(EthereumSubscribeResponse(Hash)) {
    return self.parseSubscriptionEvent(Hash);
}
/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(self: *WebSocketHandler, opts: ProofRequest, tag: ?ProofBlockTag) !RPCResponse(ProofResult) {
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
/// Returns the current Ethereum protocol version.
///
/// RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)
pub fn getProtocolVersion(self: *WebSocketHandler) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_protocolVersion);
}
/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(self: *WebSocketHandler, tx_hash: Hash) !RPCResponse(Hex) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{tx_hash},
        .method = .eth_getRawTransactionByHash,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hex, buf_writter.getWritten());
}
/// Returns the Keccak256 hash of the given message.
///
/// RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)
pub fn getSha3Hash(self: *WebSocketHandler, message: []const u8) !RPCResponse(Hash) {
    const hex_message = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(message)});
    defer self.allocator.free(hex_message);

    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{message},
        .method = .web3_sha3,
        .id = self.chain_id,
    };

    var request_buffer: [4096]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(Hash, buf_writter.getWritten());
}
/// Returns the value from a storage position at a given address.
///
/// RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)
pub fn getStorage(self: *WebSocketHandler, address: Address, storage_key: Hash, opts: BlockNumberRequest) !RPCResponse(Hash) {
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
/// Returns null if the node has finished syncing. Otherwise it will return
/// the sync progress.
///
/// RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)
pub fn getSyncStatus(self: *WebSocketHandler) !?RPCResponse(SyncProgress) {
    return self.sendBasicRequest(SyncProgress, .eth_syncing) catch null;
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *WebSocketHandler, block_hash: Hash, index: usize) !RPCResponse(Transaction) {
    return self.getTransactionByBlockHashAndIndexType(Transaction, block_hash, index);
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndexType(self: *WebSocketHandler, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
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
pub fn getTransactionByBlockNumberAndIndex(self: *WebSocketHandler, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction) {
    return self.getTransactionByBlockNumberAndIndexType(Transaction, opts, index);
}
/// Returns information about a transaction by block number and transaction index position.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndexType(self: *WebSocketHandler, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
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
pub fn getTransactionByHash(self: *WebSocketHandler, transaction_hash: Hash) !RPCResponse(Transaction) {
    return self.getTransactionByHashType(Transaction, transaction_hash);
}
/// Returns the information about a transaction requested by transaction hash.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHashType(self: *WebSocketHandler, comptime T: type, transaction_hash: Hash) !RPCResponse(T) {
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
pub fn getTransactionReceipt(self: *WebSocketHandler, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
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
/// The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// The result is an object with two fields pending and queued.
/// Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.
/// These batches themselves are maps associating nonces with actual transactions.
///
/// RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContent(self: *WebSocketHandler) !RPCResponse(TxPoolContent) {
    return self.sendBasicRequest(TxPoolContent, .txpool_content);
}
/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(self: *WebSocketHandler, from: Address) !RPCResponse([]const PoolTransactionByNonce) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{from},
        .method = .txpool_contentFrom,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    return self.sendRpcRequest([]const PoolTransactionByNonce, buf_writter.getWritten());
}
/// The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
/// This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.
///
/// RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolInspectStatus(self: *WebSocketHandler) !RPCResponse(TxPoolInspect) {
    return self.sendBasicRequest(TxPoolInspect, .txpool_inspect);
}
/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *WebSocketHandler) !RPCResponse(TxPoolStatus) {
    return self.sendBasicRequest(TxPoolStatus, .txpool_status);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *WebSocketHandler, block_hash: Hash, index: usize) !RPCResponse(Block) {
    return self.getUncleByBlockHashAndIndexType(Block, block_hash, index);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndexType(self: *WebSocketHandler, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
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
pub fn getUncleByBlockNumberAndIndex(self: *WebSocketHandler, opts: BlockNumberRequest, index: usize) !RPCResponse(Block) {
    return self.getUncleByBlockNumberAndIndexType(Block, opts, index);
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndexType(self: *WebSocketHandler, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64, usize }) = .{
            .params = .{ number, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag, usize }) = .{
            .params = .{ tag, index },
            .method = .eth_getUncleByBlockNumberAndIndex,
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
pub fn getUncleCountByBlockHash(self: *WebSocketHandler, block_hash: Hash) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *WebSocketHandler, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
}
/// Runs the selected multicall3 contracts.
/// This enables to read from multiple contract by a single `eth_call`.
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
    self: *WebSocketHandler,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) !AbiDecoded([]const Result) {
    var multicall_caller = try Multicall(.websocket).init(self);

    return multicall_caller.multicall3(targets, function_arguments, allow_failure);
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *WebSocketHandler) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *WebSocketHandler, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128) {
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

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { LogRequest }) = .{
            .params = .{opts},
            .method = .eth_newFilter,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *WebSocketHandler) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newPendingTransactionFilter);
}
/// Parses a subscription event `Value` into `T`.
/// Usefull for events that currently zabi doesn't have custom support.
pub fn parseSubscriptionEvent(self: *WebSocketHandler, comptime T: type) !RPCResponse(EthereumSubscribeResponse(T)) {
    const event = self.sub_channel.get();
    errdefer event.deinit();

    const parsed = try std.json.parseFromValueLeaky(EthereumSubscribeResponse(T), event.arena.allocator(), event.value, .{ .allocate = .alloc_always });

    return RPCResponse(EthereumSubscribeResponse(T)).fromJson(event.arena, parsed);
}
/// This is a blocking operation.
/// Best to call this in a seperate thread.
pub fn readLoopOwned(self: *WebSocketHandler) !void {
    errdefer self.deinit();
    pipe.maybeIgnoreSigpipe();

    self.ws_client.readLoop(self) catch |err| {
        wslog.debug("Read loop reported error: {s}", .{@errorName(err)});
        return;
    };
}
/// Executes a new message call immediately without creating a transaction on the block chain.
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Hex) {
    return self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *WebSocketHandler, serialized_tx: Hex) !RPCResponse(Hash) {
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
/// Writes message to websocket server and parses the reponse from it.
/// This blocks until it gets the response back from the server.
pub fn sendRpcRequest(self: *WebSocketHandler, comptime T: type, message: []u8) !RPCResponse(T) {
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.writeSocketMessage(message);

        const message_value = self.getCurrentRpcEvent();
        errdefer message_value.deinit();

        const parsed = try std.json.parseFromValueLeaky(EthereumResponse(T), message_value.arena.allocator(), message_value.value, .{ .allocate = .alloc_always });

        switch (parsed) {
            .success => |success| return RPCResponse(T).fromJson(message_value.arena, success.result),
            .@"error" => |err_message| {
                const err = self.handleErrorResponse(err_message.@"error");
                switch (err) {
                    error.TooManyRequests => {
                        // Exponential backoff
                        const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
                        wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                        std.time.sleep(std.time.ns_per_ms * backoff);
                        continue;
                    },
                    else => return err,
                }
            },
        }
    }
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstallFilter(self: *WebSocketHandler, id: usize) !RPCResponse(bool) {
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
/// Unsubscribe from different Ethereum event types with a regular RPC call
/// with eth_unsubscribe as the method and the subscriptionId as the first parameter.
///
/// RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)
pub fn unsubscribe(self: *WebSocketHandler, sub_id: u128) !RPCResponse(bool) {
    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{sub_id},
        .method = .eth_unsubscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(bool, buf_writter.getWritten());
}
/// Emits new blocks that are added to the blockchain.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
pub fn watchNewBlocks(self: *WebSocketHandler) !RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newHeads},
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Emits logs attached to a new block that match certain topic filters and address.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)
pub fn watchLogs(self: *WebSocketHandler, opts: WatchLogsRequest) !RPCResponse(u128) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const request: EthereumRequest(struct { Subscriptions, WatchLogsRequest }) = .{
        .params = .{ .logs, opts },
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Emits transaction hashes that are sent to the network and marked as "pending".
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)
pub fn watchTransactions(self: *WebSocketHandler) !RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newPendingTransactions},
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Creates a new subscription for desired events. Sends data as soon as it occurs
///
/// This expects the method to be a valid websocket subscription method.
/// Since we have no way of knowing all possible or custom RPC methods that nodes can provide.
///
/// Returns the subscription Id.
pub fn watchWebsocketEvent(self: *WebSocketHandler, method: []const u8) !RPCResponse(u128) {
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{method},
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(self: *WebSocketHandler, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
    return self.waitForTransactionReceiptType(TransactionReceipt, tx_hash, confirmations);
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// Ask for a expected type since the way that our json parser works
/// on unions it will try to parse it until it can complete it for a
/// union member. This can be slow so if you know exactly what is the
/// expected type you can pass it and it will return the json parsed
/// response.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceiptType(self: *WebSocketHandler, comptime T: type, tx_hash: Hash, confirmations: u8) !RPCResponse(T) {
    var tx: ?RPCResponse(Transaction) = null;
    defer if (tx) |t| t.deinit();

    var block_request = try self.getBlockNumber();
    defer block_request.deinit();

    var block_number = block_request.response;

    var receipt: ?RPCResponse(TransactionReceipt) = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
        error.TransactionReceiptNotFound => null,
        else => return err,
    };
    errdefer if (receipt) |tx_receipt| tx_receipt.deinit();

    if (receipt) |tx_receipt| {
        if (confirmations == 0)
            return tx_receipt;
    }

    const sub_id = try self.watchNewBlocks();
    defer sub_id.deinit();

    var retries: u8 = 0;
    var valid_confirmations: u8 = if (receipt != null) 1 else 0;
    while (true) {
        if (retries - valid_confirmations > self.retries)
            return error.FailedToGetReceipt;

        const event = try self.getNewHeadsBlockSubEvent();
        defer event.deinit();

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
                retries += 1;
                std.time.sleep(std.time.ns_per_ms * self.pooling_interval);
                continue;
            }
        }

        if (tx == null) {
            tx = self.getTransactionByHash(tx_hash) catch |err| switch (err) {
                // If it fails we keep trying
                error.TransactionNotFound => {
                    retries += 1;
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
                const current_block = try self.getBlockByNumber(.{ .include_transaction_objects = true });
                defer current_block.deinit();

                const tx_info: struct { from: Address, nonce: u64 } = switch (tx.?.response) {
                    inline else => |transactions| .{ .from = transactions.from, .nonce = transactions.nonce },
                };

                const block_transactions = switch (current_block.response) {
                    inline else => |blocks| if (blocks.transactions) |block_txs| block_txs else {
                        retries += 1;
                        continue;
                    },
                };

                const pending_transaction = switch (block_transactions) {
                    .hashes => {
                        retries += 1;
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

                    wslog.debug("Transaction was replace by a newer one", .{});

                    switch (replaced_tx) {
                        inline else => |replacement| switch (tx.?.response) {
                            inline else => |original| {
                                if (std.mem.eql(u8, &replacement.from, &original.from) and replacement.value == original.value)
                                    wslog.debug("Original transaction was repriced", .{});

                                if (replacement.to) |replaced_to| {
                                    if (std.mem.eql(u8, &replacement.from, &replaced_to) and replacement.value == 0)
                                        wslog.debug("Original transaction was canceled", .{});
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

                retries += 1;
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
            retries += 1;
            continue;
        }
    }
    const success = try self.unsubscribe(sub_id.response);
    defer success.deinit();

    if (!success.response)
        return error.FailedToUnsubscribe;

    return if (receipt) |tx_receipt| tx_receipt else error.FailedToGetReceipt;
}
/// Write messages to the websocket server.
pub fn writeSocketMessage(self: *WebSocketHandler, data: []u8) !void {
    return self.ws_client.write(data);
}

// Internal

/// Converts ethereum error codes into Zig errors.
fn handleErrorResponse(self: *WebSocketHandler, event: ErrorResponse) EthereumZigErrors {
    _ = self;

    wslog.debug("RPC error response: {s}\n", .{event.message});
    switch (event.code) {
        .ContractErrorCode => return error.EvmFailedToExecute,
        .TooManyRequests => return error.TooManyRequests,
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
}
/// Internal RPC event parser.
/// Error set is the same as std.json.
fn parseRPCEvent(self: *WebSocketHandler, request: []const u8) !JsonParsed(Value) {
    const parsed = std.json.parseFromSlice(Value, self.allocator, request, .{ .allocate = .alloc_always }) catch |err| {
        wslog.debug("Failed to parse request: {s}", .{request});

        return err;
    };

    return parsed;
}
/// Sends requests with empty params.
fn sendBasicRequest(self: *WebSocketHandler, comptime T: type, method: EthereumRpcMethods) !RPCResponse(T) {
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

/// Sends specific block_number requests.
fn sendBlockNumberRequest(self: *WebSocketHandler, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(usize) {
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
// Sends specific block_hash requests.
fn sendBlockHashRequest(self: *WebSocketHandler, block_hash: Hash, method: EthereumRpcMethods) !RPCResponse(usize) {
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
/// Sends request specific for addresses.
fn sendAddressRequest(self: *WebSocketHandler, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) !RPCResponse(T) {
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
/// Sends eth_call request
fn sendEthCallRequest(self: *WebSocketHandler, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(T) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = method,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    return self.sendRpcRequest(T, buf_writter.getWritten());
}

test "BlockByNumber" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByNumber(.{ .block_number = 10 });
        defer block_number.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByNumber(.{});
        defer block_number.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByNumber(.{ .include_transaction_objects = true });
        defer block_number.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByNumber(.{ .block_number = 1000000, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockByHash" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByHash(.{
            .block_hash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response == .beacon);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockByHash(.{
            .block_hash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
            .include_transaction_objects = true,
        });
        defer block_number.deinit();

        try testing.expect(block_number.response == .beacon);
        try testing.expect(block_number.response.beacon.transactions != null);
        try testing.expect(block_number.response.beacon.transactions.? == .objects);
    }
}

test "BlockTransactionCountByHash" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const block_number = try client.getBlockTransactionCountByHash(try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
    defer block_number.deinit();

    try testing.expect(block_number.response != 0);
}

test "BlockTransactionCountByNumber" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockTransactionCountByNumber(.{ .block_number = 100101 });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getBlockTransactionCountByNumber(.{});
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
}

test "AddressBalance" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getAddressBalance(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
            .block_number = 100101,
        });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getAddressBalance(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
}

test "AddressNonce" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getAddressTransactionCount(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
        });
        defer block_number.deinit();

        try testing.expect(block_number.response != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const block_number = try client.getAddressTransactionCount(.{
            .address = try utils.addressToBytes("0x0689f41a1461D176F722E824B682F439a9b9FDbf"),
            .block_number = 100012,
        });
        defer block_number.deinit();

        try testing.expectEqual(block_number.response, 0);
    }
}

test "BlockNumber" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const block_number = try client.getBlockNumber();
    defer block_number.deinit();

    try testing.expectEqual(block_number.response, 19062632);
}

test "GetChainId" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const chain = try client.getChainId();
    defer chain.deinit();

    try testing.expectEqual(chain.response, 1);
}

test "GetStorage" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{});
        defer storage.deinit();

        try testing.expectEqual(@as(u256, @bitCast(storage.response)), 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{ .block_number = 101010 });
        defer storage.deinit();

        try testing.expectEqual(@as(u256, @bitCast(storage.response)), 0);
    }
}

test "GetAccounts" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const accounts = try client.getAccounts();
    defer accounts.deinit();

    try testing.expectEqual(accounts.response.len, 10);
    try testing.expectEqualSlices(u8, &accounts.response[0], &try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"));
}

test "GetContractCode" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const code = try client.getContractCode(.{
            .address = try utils.addressToBytes("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
        });
        defer code.deinit();

        try testing.expect(code.response.len != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const code = try client.getContractCode(.{
            .address = try utils.addressToBytes("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            .block_number = 101010,
        });
        defer code.deinit();

        try testing.expectEqual(code.response.len, 0);
    }
}

test "GetTransactionByHash" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const tx = try client.getTransactionByHash(try utils.hashToBytes("0x360bf48bf75f0020d05cc97526b246d67c266dcf91897c01cf7acfe94fe2154e"));
    defer tx.deinit();

    try testing.expect(tx.response == .london);
    try testing.expectEqual(tx.response.london.blockHash, try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
}

test "GetReceipt" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const receipt = try client.getTransactionReceipt(try utils.hashToBytes("0x360bf48bf75f0020d05cc97526b246d67c266dcf91897c01cf7acfe94fe2154e"));
    defer receipt.deinit();

    try testing.expect(receipt.response == .legacy);
    try testing.expectEqual(receipt.response.legacy.blockHash, try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
}

test "GetFilter" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterChanges);
        defer filter.deinit();

        try testing.expectEqual(filter.response.len, 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterLogs);
        defer filter.deinit();

        try testing.expectEqual(filter.response.len, 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        try testing.expectError(error.InvalidRpcMethod, client.getFilterOrLogChanges(0, .eth_chainId));
    }
}

test "GetGasPrice" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const gas = try client.getGasPrice();
    defer gas.deinit();

    try testing.expect(gas.response != 0);
}

test "GetUncleCountByBlockHash" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const uncle = try client.getUncleCountByBlockHash(try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"));
    defer uncle.deinit();

    try testing.expectEqual(uncle.response, 0);
}

test "GetUncleCountByBlockNumber" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const uncle = try client.getUncleCountByBlockNumber(.{});
        defer uncle.deinit();

        try testing.expectEqual(uncle.response, 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const uncle = try client.getUncleCountByBlockNumber(.{ .block_number = 101010 });
        defer uncle.deinit();

        try testing.expectEqual(uncle.response, 0);
    }
}

test "GetUncleByBlockNumberAndIndex" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        try testing.expectError(error.InvalidBlockNumberOrIndex, client.getUncleByBlockNumberAndIndex(.{}, 0));
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const uncle = try client.getUncleByBlockNumberAndIndex(.{ .block_number = 15537381 }, 0);
        defer uncle.deinit();

        try testing.expect(uncle.response == .legacy);
    }
}

test "GetUncleByBlockHashAndIndex" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const tx = try client.getUncleByBlockHashAndIndex(try utils.hashToBytes("0x4e216c95f527e9ba0f1161a1c4609b893302c704f05a520da8141ca91878f63e"), 0);
    defer tx.deinit();

    try testing.expect(tx.response == .legacy);
}

test "GetTransactionByBlockNumberAndIndex" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        try testing.expectError(error.TransactionNotFound, client.getTransactionByBlockNumberAndIndex(.{}, 0));
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const tx = try client.getTransactionByBlockNumberAndIndex(.{ .block_number = 15537381 }, 0);
        defer tx.deinit();

        try testing.expect(tx.response == .london);
    }
}

test "EstimateGas" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        try testing.expectError(error.TransactionRejected, client.estimateGas(.{ .london = .{ .gas = 10 } }, .{}));
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateGas(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();

        try testing.expect(fee.response != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateGas(.{ .legacy = .{ .value = 10 } }, .{});
        defer fee.deinit();

        try testing.expect(fee.response != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();

        try testing.expect(fee.response != 0);
    }
}

test "CreateAccessList" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const access = try client.createAccessList(.{ .london = .{ .value = 10 } }, .{});
        defer access.deinit();

        try testing.expect(access.response.gasUsed != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        try testing.expectError(error.InternalError, client.createAccessList(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 }));
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const access = try client.createAccessList(.{ .legacy = .{ .value = 10 } }, .{});
        defer access.deinit();

        try testing.expect(access.response.gasUsed != 0);
    }
}

test "GetNetworkPeerCount" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    try testing.expectError(error.InvalidParams, client.getNetworkPeerCount());
}

test "GetNetworkVersionId" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const id = try client.getNetworkVersionId();
    defer id.deinit();

    try testing.expectEqual(id.response, 1);
}

test "GetNetworkListenStatus" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const id = try client.getNetworkListenStatus();
    defer id.deinit();

    try testing.expectEqual(id.response, true);
}

test "GetSha3Hash" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    try testing.expectError(error.InvalidParams, client.getSha3Hash("foobar"));
}

test "GetClientVersion" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const version = try client.getClientVersion();
    defer version.deinit();

    try testing.expect(version.response.len != 0);
}

test "BlobBaseFee" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const base_fee = try client.blobBaseFee();
    defer base_fee.deinit();

    try testing.expectEqual(base_fee.response, 0);
}

test "EstimateBlobMaxFeePerGas" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const base_fee = try client.estimateBlobMaxFeePerGas();

    try testing.expect(base_fee != 0);
}

test "EstimateMaxFeePerGas" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const fees = try client.estimateMaxFeePerGas();
    defer fees.deinit();

    try testing.expect(fees.response != 0);
}

test "EstimateFeePerGas" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateFeesPerGas(.{ .london = .{} }, null);

        try testing.expect(fee.london.max_fee_gas != 0);
        try testing.expect(fee.london.max_priority_fee != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateFeesPerGas(.{ .legacy = .{} }, null);

        try testing.expect(fee.legacy.gas_price != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const fee = try client.estimateFeesPerGas(.{ .london = .{} }, 1000);

        try testing.expect(fee.london.max_fee_gas != 0);
        try testing.expect(fee.london.max_priority_fee != 0);
    }
}

test "GetProof" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{}, .blockNumber = 101010 }, null);
        defer proofs.deinit();

        try testing.expect(proofs.response.balance != 0);
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{} }, .latest);
        defer proofs.deinit();

        try testing.expect(proofs.response.balance != 0);
    }
}

test "GetLogs" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const logs = try client.getLogs(.{ .toBlock = 101010, .fromBlock = 101010 }, null);
        defer logs.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const logs = try client.getLogs(.{}, .latest);
        defer logs.deinit();
    }
}

test "NewLogFilter" {
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const logs = try client.newLogFilter(.{}, .latest);
        defer logs.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const logs = try client.newLogFilter(.{ .fromBlock = 101010, .toBlock = 101010 }, null);
        defer logs.deinit();
    }
}

test "NewBlockFilter" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const block_id = try client.newBlockFilter();
    defer block_id.deinit();
}

test "NewPendingTransactionFilter" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const tx_id = try client.newPendingTransactionFilter();
    defer tx_id.deinit();
}

test "UninstallFilter" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const status = try client.uninstallFilter(1);
    defer status.deinit();
}

test "GetProtocolVersion" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    try testing.expectError(error.InvalidParams, client.getProtocolVersion());
}

test "SyncStatus" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

    const status = try client.getSyncStatus();
    defer if (status) |s| s.deinit();
}

test "FeeHistory" {
    if (true) return error.SkipZigTest;

    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, null);
        defer status.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        var client: WebSocketHandler = undefined;
        defer client.deinit();

        const uri = try std.Uri.parse("http://127.0.0.1:6969/");
        try client.init(.{
            .allocator = testing.allocator,
            .uri = uri,
        });

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
}

test "Multicall" {
    var client: WebSocketHandler = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("http://127.0.0.1:6969/");
    try client.init(.{
        .allocator = testing.allocator,
        .uri = uri,
    });

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
        MulticallTargets{ .function = supply, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
        MulticallTargets{ .function = balance, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
    };

    const res = try client.multicall3(a, .{ {}, .{try utils.addressToBytes("0xFded38DF0180039867E54EBdec2012D534862cE3")} }, true);
    defer res.deinit();

    try testing.expect(res.result.len != 0);
    try testing.expectEqual(res.result[0].success, true);
}
