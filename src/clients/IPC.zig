const block = @import("../types/block.zig");
const meta = @import("../meta/utils.zig");
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

const assert = std.debug.assert;

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
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const IpcReader = @import("ipc_reader.zig").IpcReader;
const JsonParsed = std.json.Parsed;
const Log = log.Log;
const LogRequest = log.LogRequest;
const LogTagRequest = log.LogTagRequest;
const Logs = log.Logs;
const Mutex = std.Thread.Mutex;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const RPCResponse = types.RPCResponse;
const Stack = @import("../utils/stack.zig").Stack;
const Stream = std.net.Stream;
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

const IPC = @This();

const ipclog = std.log.scoped(.ipc);

pub const IPCErrors = error{
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
} || Allocator.Error || std.fmt.ParseIntError || std.Uri.ParseError || EthereumZigErrors;

/// Set of intial options for the IPC Client.
pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// The reader buffer growth rate
    growth_rate: ?usize = null,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
    /// The path for the IPC path
    path: []const u8,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// Retry count for failed connections to server.
    retries: u8 = 5,
};

/// The allocator that will manage the connections memory
allocator: Allocator,
/// The base fee multiplier used to estimate the gas fees in a transaction
base_fee_multiplier: f64,
/// The chain id of the attached network
chain_id: usize,
/// If the client is closed.
closed: bool,
/// The IPC net stream to read and write requests.
ipc_reader: IpcReader,
/// Mutex to manage locks between threads
mutex: Mutex = .{},
/// Callback function for when the connection is closed.
onClose: ?*const fn () void,
/// Callback function that will run once a socket event is parsed
onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void,
/// Callback function that will run once a error is parsed.
onError: ?*const fn (args: []const u8) anyerror!void,
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// Retry count for failed connections or requests.
retries: u8,
/// Channel used to communicate between threads on rpc events.
rpc_channel: Stack(JsonParsed(Value)),
/// Channel used to communicate between threads on subscription events.
sub_channel: Channel(JsonParsed(Value)),

/// Starts the IPC client and create the connection.
/// This will also start the read loop in a seperate thread.
pub fn init(self: *IPC, opts: InitOptions) !void {
    const chain_id: Chains = opts.chain_id orelse .ethereum;

    self.* = .{
        .allocator = opts.allocator,
        .base_fee_multiplier = opts.base_fee_multiplier,
        .chain_id = @intFromEnum(chain_id),
        .closed = false,
        .onClose = opts.onClose,
        .onError = opts.onError,
        .onEvent = opts.onEvent,
        .pooling_interval = opts.pooling_interval,
        .retries = opts.retries,
        .rpc_channel = Stack(JsonParsed(Value)).init(self.allocator, null),
        .sub_channel = Channel(JsonParsed(Value)).init(self.allocator),
        .ipc_reader = undefined,
    };

    errdefer {
        self.rpc_channel.deinit();
        self.sub_channel.deinit();
    }

    self.ipc_reader = try IpcReader.init(opts.allocator, try self.connect(opts.path), null);

    const thread = try std.Thread.spawn(.{}, readLoopOwnedThread, .{self});
    thread.detach();
}
/// Clears memory, closes the stream and destroys any
/// previously created pointers.
///
/// All future calls will deadlock.
pub fn deinit(self: *IPC) void {
    self.mutex.lock();

    while (@atomicRmw(bool, &self.closed, .Xchg, true, .seq_cst)) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }

    while (self.sub_channel.getOrNull()) |response| {
        response.deinit();
    }

    while (self.rpc_channel.popOrNull()) |response| {
        response.deinit();
    }

    self.ipc_reader.deinit();
    self.rpc_channel.deinit();
    self.sub_channel.deinit();
}
/// Connects to the socket. Will try to reconnect in case of failures.
/// Fails when match retries are reached or a invalid ipc path is provided
pub fn connect(self: *IPC, path: []const u8) !Stream {
    if (!std.mem.endsWith(u8, path, ".ipc"))
        return error.InvalidIPCPath;

    var retries: u8 = 0;
    const stream = while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.FailedToConnect;

        switch (retries) {
            0...2 => {},
            else => {
                const sleep_timing: u64 = @min(10_000, self.pooling_interval * retries);
                std.time.sleep(sleep_timing * std.time.ns_per_ms);
            },
        }

        const socket_stream = std.net.connectUnixSocket(path) catch |err| {
            ipclog.debug("Failed to connect: {s}", .{@errorName(err)});
            continue;
        };

        break socket_stream;
    };

    return stream;
}
/// Grabs the current base blob fee.
///
/// RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)
pub fn blobBaseFee(self: *IPC) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_blobBaseFee);
}
/// Create an accessList of addresses and storageKeys for an transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}
/// Estimate the gas used for blobs
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation
pub fn estimateBlobMaxFeePerGas(self: *IPC) !Gwei {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else base.response - gas_price.response;
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(self: *IPC, call_object: EthCall, base_fee_per_gas: ?Gwei) !EstimateFeeReturn {
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
pub fn estimateGas(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Gwei) {
    return self.sendEthCallRequest(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *IPC, base_fee_per_gas: ?Gwei) !Gwei {
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
pub fn estimateMaxFeePerGas(self: *IPC) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_maxPriorityFeePerGas);
}
/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(self: *IPC, blockCount: u64, newest_block: BlockNumberRequest, reward_percentil: ?[]const f64) !RPCResponse(FeeHistory) {
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
pub fn getAccounts(self: *IPC) !RPCResponse([]const Address) {
    return self.sendBasicRequest([]const Address, .eth_accounts);
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *IPC, opts: BalanceRequest) !RPCResponse(Wei) {
    return self.sendAddressRequest(Wei, opts, .eth_getBalance);
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *IPC, opts: BalanceRequest) !RPCResponse(u64) {
    return self.sendAddressRequest(u64, opts, .eth_getTransactionCount);
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(self: *IPC, opts: BlockHashRequest) !RPCResponse(Block) {
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
pub fn getBlockByHashType(self: *IPC, comptime T: type, opts: BlockHashRequest) !RPCResponse(T) {
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
pub fn getBlockByNumber(self: *IPC, opts: BlockRequest) !RPCResponse(Block) {
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
pub fn getBlockByNumberType(self: *IPC, comptime T: type, opts: BlockRequest) !RPCResponse(T) {
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
pub fn getBlockNumber(self: *IPC) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blockNumber);
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *IPC, block_hash: Hash) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *IPC, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *IPC) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_chainId);
}
/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *IPC) !RPCResponse([]const u8) {
    return self.sendBasicRequest([]const u8, .web3_clientVersion);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *IPC, opts: BalanceRequest) !RPCResponse(Hex) {
    return self.sendAddressRequest(Hex, opts, .eth_getCode);
}
/// Get the first event of the rpc channel.
///
/// Only call this if you are sure that the channel has messages
/// because this will block until a message is able to be fetched.
pub fn getCurrentRpcEvent(self: *IPC) JsonParsed(Value) {
    return self.rpc_channel.pop();
}
/// Get the first event of the subscription channel.
///
/// Only call this if you are sure that the channel has messages
/// because this will block until a message is able to be fetched.
pub fn getCurrentSubscriptionEvent(self: *IPC) JsonParsed(Value) {
    return self.sub_channel.get();
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *IPC, filter_id: u128, method: EthereumRpcMethods) !RPCResponse(Logs) {
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
pub fn getGasPrice(self: *IPC) !RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_gasPrice);
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(Logs) {
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
pub fn getLogsSubEvent(self: *IPC) !RPCResponse(EthereumSubscribeResponse(Log)) {
    return self.parseSubscriptionEvent(Log);
}
/// Parses the `Value` in the sub-channel as a new heads block event
pub fn getNewHeadsBlockSubEvent(self: *IPC) !RPCResponse(EthereumSubscribeResponse(Block)) {
    return self.parseSubscriptionEvent(Block);
}
/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *IPC) !RPCResponse(bool) {
    return self.sendBasicRequest(bool, .net_listening);
}
/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *IPC) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_peerCount);
}
/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *IPC) !RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_version);
}
/// Parses the `Value` in the sub-channel as a pending transaction hash event
pub fn getPendingTransactionsSubEvent(self: *IPC) !RPCResponse(EthereumSubscribeResponse(Hash)) {
    return self.parseSubscriptionEvent(Hash);
}
/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(self: *IPC, opts: ProofRequest, tag: ?ProofBlockTag) !RPCResponse(ProofResult) {
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
pub fn getProtocolVersion(self: *IPC) !RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_protocolVersion);
}
/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(self: *IPC, tx_hash: Hash) !RPCResponse(Hex) {
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
pub fn getSha3Hash(self: *IPC, message: []const u8) !RPCResponse(Hash) {
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
pub fn getStorage(self: *IPC, address: Address, storage_key: Hash, opts: BlockNumberRequest) !RPCResponse(Hash) {
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
pub fn getSyncStatus(self: *IPC) !?RPCResponse(SyncProgress) {
    return self.sendBasicRequest(SyncProgress, .eth_syncing) catch null;
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *IPC, block_hash: Hash, index: usize) !RPCResponse(Transaction) {
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
pub fn getTransactionByBlockHashAndIndexType(self: *IPC, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
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
pub fn getTransactionByBlockNumberAndIndex(self: *IPC, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction) {
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
pub fn getTransactionByBlockNumberAndIndexType(self: *IPC, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
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
pub fn getTransactionByHash(self: *IPC, transaction_hash: Hash) !RPCResponse(Transaction) {
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
pub fn getTransactionByHashType(self: *IPC, comptime T: type, transaction_hash: Hash) !RPCResponse(T) {
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
pub fn getTransactionReceipt(self: *IPC, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
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
pub fn getTxPoolContent(self: *IPC) !RPCResponse(TxPoolContent) {
    return self.sendBasicRequest(TxPoolContent, .txpool_content);
}
/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(self: *IPC, from: Address) !RPCResponse([]const PoolTransactionByNonce) {
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
pub fn getTxPoolInspectStatus(self: *IPC) !RPCResponse(TxPoolInspect) {
    return self.sendBasicRequest(TxPoolInspect, .txpool_inspect);
}
/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *IPC) !RPCResponse(TxPoolStatus) {
    return self.sendBasicRequest(TxPoolStatus, .txpool_status);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *IPC, block_hash: Hash, index: usize) !RPCResponse(Block) {
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
pub fn getUncleByBlockHashAndIndexType(self: *IPC, comptime T: type, block_hash: Hash, index: usize) !RPCResponse(T) {
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
pub fn getUncleByBlockNumberAndIndex(self: *IPC, opts: BlockNumberRequest, index: usize) !RPCResponse(Block) {
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
pub fn getUncleByBlockNumberAndIndexType(self: *IPC, comptime T: type, opts: BlockNumberRequest, index: usize) !RPCResponse(T) {
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
pub fn getUncleCountByBlockHash(self: *IPC, block_hash: Hash) !RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *IPC, opts: BlockNumberRequest) !RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *IPC) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128) {
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
pub fn newPendingTransactionFilter(self: *IPC) !RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newPendingTransactionFilter);
}
/// Creates a read loop to read the socket messages.
/// If a message is too long it will double the buffer size to read the message.
pub fn readLoop(self: *IPC) !void {
    while (true) {
        const message = self.ipc_reader.readMessage() catch |err| switch (err) {
            error.Closed, error.ConnectionResetByPeer, error.BrokenPipe => {
                _ = @cmpxchgStrong(bool, &self.closed, false, true, .monotonic, .monotonic);
                return;
            },
            else => return,
        };

        ipclog.debug("Got message: {s}", .{message});

        const parsed = self.parseRPCEvent(message) catch {
            if (self.onError) |onError| {
                try onError(message);
            }
            const timeout = std.mem.toBytes(std.posix.timeval{
                .sec = @intCast(0),
                .usec = @intCast(1000),
            });
            try std.posix.setsockopt(self.ipc_reader.stream.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &timeout);

            return error.FailedToJsonParseResponse;
        };
        errdefer parsed.deinit();

        if (parsed.value != .object)
            return error.InvalidTypeMessage;

        // You need to check what type of event it is.
        if (self.onEvent) |onEvent| {
            try onEvent(parsed);
        }

        if (parsed.value.object.getKey("params") != null) {
            self.sub_channel.put(parsed);
            continue;
        }

        self.rpc_channel.push(parsed);
    }
}
/// Function prepared to start the read loop in a seperate thread.
pub fn readLoopOwnedThread(self: *IPC) !void {
    errdefer self.deinit();
    pipe.maybeIgnoreSigpipe();

    self.readLoop() catch |err| {
        ipclog.debug("Read loop reported error: {s}", .{@errorName(err)});
        return;
    };
}
/// Parses a subscription event `Value` into `T`.
/// Usefull for events that currently zabi doesn't have custom support.
pub fn parseSubscriptionEvent(self: *IPC, comptime T: type) !RPCResponse(EthereumSubscribeResponse(T)) {
    const event = self.sub_channel.get();
    errdefer event.deinit();

    const parsed = try std.json.parseFromValueLeaky(EthereumSubscribeResponse(T), event.arena.allocator(), event.value, .{ .allocate = .alloc_always });

    return RPCResponse(EthereumSubscribeResponse(T)).fromJson(event.arena, parsed);
}
/// Executes a new message call immediately without creating a transaction on the block chain.
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(Hex) {
    return self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *IPC, serialized_tx: Hex) !RPCResponse(Hash) {
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
pub fn sendRpcRequest(self: *IPC, comptime T: type, message: []u8) !RPCResponse(T) {
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
                        ipclog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

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
pub fn uninstallFilter(self: *IPC, id: usize) !RPCResponse(bool) {
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
pub fn unsubscribe(self: *IPC, sub_id: u128) !RPCResponse(bool) {
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
pub fn watchNewBlocks(self: *IPC) !RPCResponse(u128) {
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
pub fn watchLogs(self: *IPC, opts: WatchLogsRequest) !RPCResponse(u128) {
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
pub fn watchTransactions(self: *IPC) !RPCResponse(u128) {
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
pub fn watchWebsocketEvent(self: *IPC, method: []const u8) !RPCResponse(u128) {
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
pub fn waitForTransactionReceipt(self: *IPC, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
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
pub fn waitForTransactionReceiptType(self: *IPC, comptime T: type, tx_hash: Hash, confirmations: u8) !RPCResponse(T) {
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

                    ipclog.debug("Transaction was replace by a newer one", .{});

                    switch (replaced_tx) {
                        inline else => |replacement| switch (tx.?.response) {
                            inline else => |original| {
                                if (std.mem.eql(u8, &replacement.from, &original.from) and replacement.value == original.value)
                                    ipclog.debug("Original transaction was repriced", .{});

                                if (replacement.to) |replaced_to| {
                                    if (std.mem.eql(u8, &replacement.from, &replaced_to) and replacement.value == 0)
                                        ipclog.debug("Original transaction was canceled", .{});
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
pub fn writeSocketMessage(self: *IPC, data: []u8) !void {
    return self.ipc_reader.writeMessage(data);
}

// Internals

/// Handles how an error event should behave.
fn handleErrorEvent(self: *IPC, error_event: EthereumErrorResponse, retries: usize) !void {
    const err = self.handleErrorResponse(error_event.@"error");

    switch (err) {
        error.TooManyRequests => {
            // Exponential backoff
            const backoff: u64 = std.math.shl(u8, 1, retries) * @as(u64, @intCast(200));
            ipclog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

            std.time.sleep(std.time.ns_per_ms * backoff);
        },
        else => return err,
    }
}
/// Converts ethereum error codes into Zig errors.
fn handleErrorResponse(self: *IPC, event: ErrorResponse) EthereumZigErrors {
    _ = self;

    ipclog.debug("RPC error response: {s}\n", .{event.message});
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
fn parseRPCEvent(self: *IPC, request: []const u8) !JsonParsed(Value) {
    const parsed = std.json.parseFromSlice(Value, self.allocator, request, .{ .allocate = .alloc_always }) catch |err| {
        ipclog.debug("Failed to parse request: {s}", .{request});

        return err;
    };

    return parsed;
}
/// Sends requests with empty params.
fn sendBasicRequest(self: *IPC, comptime T: type, method: EthereumRpcMethods) !RPCResponse(T) {
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
fn sendBlockNumberRequest(self: *IPC, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(usize) {
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
fn sendBlockHashRequest(self: *IPC, block_hash: Hash, method: EthereumRpcMethods) !RPCResponse(usize) {
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
fn sendAddressRequest(self: *IPC, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) !RPCResponse(T) {
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
fn sendEthCallRequest(self: *IPC, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) !RPCResponse(T) {
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
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByNumber(.{ .block_number = 10 });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByNumber(.{});
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByNumber(.{ .include_transaction_objects = true });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByNumber(.{ .block_number = 1000000, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockByHash" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByHash(.{ .block_hash = [_]u8{0} ** 32 });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockByHash(.{ .block_hash = [_]u8{0} ** 32, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockTransactionCountByHash" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const block_number = try client.getBlockTransactionCountByHash([_]u8{0} ** 32);
    defer block_number.deinit();
}

test "BlockTransactionCountByNumber" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockTransactionCountByNumber(.{ .block_number = 100101 });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getBlockTransactionCountByNumber(.{});
        defer block_number.deinit();
    }
}

test "AddressBalance" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getAddressBalance(.{ .address = [_]u8{0} ** 20, .block_number = 100101 });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getAddressBalance(.{ .address = [_]u8{0} ** 20 });
        defer block_number.deinit();
    }
}

test "AddressNonce" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getAddressTransactionCount(.{ .address = [_]u8{0} ** 20 });
        defer block_number.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const block_number = try client.getAddressTransactionCount(.{ .address = [_]u8{0} ** 20, .block_number = 100012 });
        defer block_number.deinit();
    }
}

test "BlockNumber" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const block_number = try client.getBlockNumber();
    defer block_number.deinit();
}

test "GetChainId" {
    // CI dislikes this test!
    if (true) return error.SkipZigTest;

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    try testing.expectError(error.InvalidChainId, client.getChainId());
}

test "GetStorage" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{});
        defer storage.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{ .block_number = 101010 });
        defer storage.deinit();
    }
}

test "GetAccounts" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const accounts = try client.getAccounts();
    defer accounts.deinit();
}

test "GetContractCode" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const code = try client.getContractCode(.{ .address = [_]u8{0} ** 20 });
        defer code.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const code = try client.getContractCode(.{ .address = [_]u8{0} ** 20, .block_number = 101010 });
        defer code.deinit();
    }
}

test "GetTransactionByHash" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const tx = try client.getTransactionByHash([_]u8{0} ** 32);
    defer tx.deinit();
}

test "GetReceipt" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const receipt = try client.getTransactionReceipt([_]u8{0} ** 32);
    defer receipt.deinit();
}

test "GetFilter" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterChanges);
        defer filter.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterLogs);
        defer filter.deinit();
    }
    {
        // CI dislikes this test!
        if (true) return error.SkipZigTest;

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        try testing.expectError(error.InvalidRpcMethod, client.getFilterOrLogChanges(0, .eth_chainId));
    }
}

test "GetGasPrice" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const gas = try client.getGasPrice();
    defer gas.deinit();
}

test "GetUncleCountByBlockHash" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const uncle = try client.getUncleCountByBlockHash([_]u8{0} ** 32);
    defer uncle.deinit();
}

test "GetUncleCountByBlockNumber" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const uncle = try client.getUncleCountByBlockNumber(.{});
        defer uncle.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const uncle = try client.getUncleCountByBlockNumber(.{ .block_number = 101010 });
        defer uncle.deinit();
    }
}

test "GetUncleByBlockNumberAndIndex" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const uncle = try client.getUncleByBlockNumberAndIndex(.{}, 0);
        defer uncle.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const uncle = try client.getUncleByBlockNumberAndIndex(.{ .block_number = 101010 }, 0);
        defer uncle.deinit();
    }
}

test "GetUncleByBlockHashAndIndex" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const tx = try client.getUncleByBlockHashAndIndex([_]u8{0} ** 32, 0);
    defer tx.deinit();
}

test "GetTransactionByBlockNumberAndIndex" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const tx = try client.getTransactionByBlockNumberAndIndex(.{}, 0);
        defer tx.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const tx = try client.getTransactionByBlockNumberAndIndex(.{ .block_number = 101010 }, 0);
        defer tx.deinit();
    }
}

test "EstimateGas" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const fee = try client.estimateGas(.{ .london = .{ .gas = 10 } }, .{});
        defer fee.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const fee = try client.estimateGas(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const fee = try client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{});
        defer fee.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const fee = try client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();
    }
}

test "CreateAccessList" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const access = try client.createAccessList(.{ .london = .{ .gas = 10 } }, .{});
        defer access.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const access = try client.createAccessList(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer access.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const access = try client.createAccessList(.{ .legacy = .{ .gas = 10 } }, .{});
        defer access.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const access = try client.createAccessList(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer access.deinit();
    }
}

test "GetNetworkPeerCount" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const count = try client.getNetworkPeerCount();
    defer count.deinit();
}

test "GetNetworkVersionId" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const id = try client.getNetworkVersionId();
    defer id.deinit();
}

test "GetNetworkListenStatus" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const status = try client.getNetworkListenStatus();
    defer status.deinit();
}

test "GetSha3Hash" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const hash = try client.getSha3Hash("foobar");
    defer hash.deinit();
}

test "GetClientVersion" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const version = try client.getClientVersion();
    defer version.deinit();
}

test "BlobBaseFee" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const blob = try client.blobBaseFee();
    defer blob.deinit();
}

test "EstimateBlobMaxFeePerGas" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    _ = try client.estimateBlobMaxFeePerGas();
}

test "EstimateFeePerGas" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        _ = try client.estimateFeesPerGas(.{ .london = .{} }, null);
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        _ = try client.estimateFeesPerGas(.{ .legacy = .{} }, null);
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        _ = try client.estimateFeesPerGas(.{ .london = .{} }, 1000);
    }
}

test "EstimateMaxFeePerGas" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const max = try client.estimateMaxFeePerGas();
    defer max.deinit();
}

test "GetProof" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{}, .blockNumber = 101010 }, null);
        defer proofs.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{} }, .latest);
        defer proofs.deinit();
    }
}

test "GetLogs" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const logs = try client.getLogs(.{ .toBlock = 101010, .fromBlock = 101010 }, null);
        defer logs.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const logs = try client.getLogs(.{}, .latest);
        defer logs.deinit();
    }
}

test "NewLogFilter" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const logs = try client.newLogFilter(.{}, .latest);
        defer logs.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const logs = try client.newLogFilter(.{ .fromBlock = 101010, .toBlock = 101010 }, null);
        defer logs.deinit();
    }
}

test "NewBlockFilter" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const block_id = try client.newBlockFilter();
    defer block_id.deinit();
}

test "NewPendingTransactionFilter" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const tx_id = try client.newPendingTransactionFilter();
    defer tx_id.deinit();
}

test "UninstalllFilter" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const status = try client.uninstallFilter(1);
    defer status.deinit();
}

test "GetProtocolVersion" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const version = try client.getProtocolVersion();
    defer version.deinit();
}

test "SyncStatus" {
    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

    const status = try client.getSyncStatus();
    defer if (status) |s| s.deinit();
}

test "FeeHistory" {
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const status = try client.feeHistory(10, .{}, null);
        defer status.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, null);
        defer status.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{ .allocator = testing.allocator, .path = "/tmp/zabi.ipc" });

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
}
