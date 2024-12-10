const block = zabi_types.block;
const decoder = @import("zabi-decoding").abi_decoder;
const http = std.http;
const log = zabi_types.log;
const network = @import("network.zig");
const meta = zabi_meta.utils;
const meta_abi = zabi_meta.abi;
const multicall = @import("multicall.zig");
const pipe = zabi_utils.pipe;
const proof = zabi_types.proof;
const std = @import("std");
const sync = zabi_types.sync;
const testing = std.testing;
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const txpool = zabi_types.txpool;
const zabi_meta = @import("zabi-meta");
const zabi_types = @import("zabi-types");
const zabi_utils = @import("zabi-utils");

const assert = std.debug.assert;

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
const Channel = zabi_utils.channel.Channel;
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
const Multicall = multicall.Multicall;
const MulticallArguments = multicall.MulticallArguments;
const MulticallTargets = multicall.MulticallTargets;
const Mutex = std.Thread.Mutex;
const NetworkConfig = network.NetworkConfig;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const ProofBlockTag = block.ProofBlockTag;
const ProofRequest = proof.ProofRequest;
const Result = multicall.Result;
const RPCResponse = types.RPCResponse;
const Scanner = std.json.Scanner;
const SetSockOptError = std.posix.SetSockOptError;
const Stack = zabi_utils.stack.Stack;
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

/// Set of possible errors when starting the client.
pub const InitErrors = Allocator.Error || std.Thread.SpawnError || error{ InvalidNetworkConfig, InvalidIPCPath, FailedToConnect };

/// Set of possible errors when reading from the socket.
pub const ReadLoopErrors = SetSockOptError || error{ FailedToJsonParseResponse, Closed, InvalidTypeMessage, UnexpectedError };

/// Set of possible errors when send a rpc request.
pub const SendRpcRequestErrors = Allocator.Error || EthereumZigErrors || std.posix.WriteError || ParseFromValueError || error{ReachedMaxRetryLimit};

/// Set of generic errors when sending a rpc request.
pub const BasicRequestErrors = SendRpcRequestErrors || error{NoSpaceLeft};

/// Set of intial options for the IPC Client.
pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The reader buffer growth rate
    growth_rate: ?usize = null,
    /// The target chains config.
    network_config: NetworkConfig,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
};

/// The allocator that will manage the connections memory
allocator: Allocator,
/// The IPC net stream to read and write requests.
ipc_reader: IpcReader,
/// The target chain network configuration. Check `NetworkConfig` for more details.
network_config: NetworkConfig,
/// Callback function for when the connection is closed.
onClose: ?*const fn () void,
/// Callback function that will run once a socket event is parsed
onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void,
/// Callback function that will run once a error is parsed.
onError: ?*const fn (args: []const u8) anyerror!void,
/// Channel used to communicate between threads on rpc events.
rpc_channel: Stack(JsonParsed(Value)),
/// Channel used to communicate between threads on subscription events.
sub_channel: Channel(JsonParsed(Value)),

/// Starts the IPC client and create the connection.
///
/// This will also start the read loop in a seperate thread.
///
/// **Example**
/// ```zig
///  var client = try IPC.init(.{
///     .allocator = testing.allocator,
///     .network_config = .{
///         .endpoint = .{ .path = "/tmp/anvil.ipc" },
///     },
///  });
///  defer client.deinit();
/// ```
pub fn init(opts: InitOptions) InitErrors!*IPC {
    const self = try opts.allocator.create(IPC);
    errdefer opts.allocator.destroy(self);

    if (opts.network_config.endpoint != .path)
        return error.InvalidNetworkConfig;

    self.* = .{
        .allocator = opts.allocator,
        .ipc_reader = undefined,
        .network_config = opts.network_config,
        .onClose = opts.onClose,
        .onError = opts.onError,
        .onEvent = opts.onEvent,
        .rpc_channel = Stack(JsonParsed(Value)).init(opts.allocator, null),
        .sub_channel = Channel(JsonParsed(Value)).init(opts.allocator),
    };

    errdefer {
        self.rpc_channel.deinit();
        self.sub_channel.deinit();
    }

    self.ipc_reader = .{
        .allocator = opts.allocator,
        .buffer = try opts.allocator.alloc(u8, opts.growth_rate orelse std.math.maxInt(u16)),
        .growth_rate = opts.growth_rate orelse std.math.maxInt(u16),
        .stream = undefined,
        .closed = false,
        .message_end = 0,
        .position = 0,
        .message_start = 0,
    };

    self.ipc_reader.stream = try self.connect(opts.network_config.endpoint.path);

    const thread = try std.Thread.spawn(.{}, readLoopOwnedThread, .{self});
    thread.detach();

    return self;
}
/// Clears memory, closes the stream and destroys any
/// previously created pointers.
///
/// All future calls will deadlock.
pub fn deinit(self: *IPC) void {
    while (self.sub_channel.getOrNull()) |response| {
        response.deinit();
    }

    while (self.rpc_channel.popOrNull()) |response| {
        response.deinit();
    }

    self.rpc_channel.deinit();
    self.sub_channel.deinit();
    self.ipc_reader.deinit();

    const allocator = self.allocator;
    allocator.destroy(self);
}
/// Connects to the socket. Will try to reconnect in case of failures.\
/// Fails when match retries are reached or a invalid ipc path is provided
pub fn connect(self: *IPC, path: []const u8) error{ InvalidIPCPath, FailedToConnect }!Stream {
    if (!std.mem.endsWith(u8, path, ".ipc"))
        return error.InvalidIPCPath;

    var retries: u8 = 0;
    const stream = while (true) : (retries += 1) {
        if (retries > self.network_config.retries) {
            @atomicStore(bool, &self.ipc_reader.closed, true, .release);
            return error.FailedToConnect;
        }

        switch (retries) {
            0...2 => {},
            else => {
                const sleep_timing: u64 = @min(5_000, self.network_config.pooling_interval * retries);
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
pub fn blobBaseFee(self: *IPC) BasicRequestErrors!RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_blobBaseFee);
}
/// Create an accessList of addresses and storageKeys for a transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(AccessListResult) {
    return self.sendEthCallRequest(AccessListResult, call_object, opts, .eth_createAccessList);
}
/// Estimate the gas used for blobs
/// Uses `blobBaseFee` and `gasPrice` to calculate this estimation
pub fn estimateBlobMaxFeePerGas(self: *IPC) BasicRequestErrors!Gwei {
    const base = try self.blobBaseFee();
    defer base.deinit();

    const gas_price = try self.getGasPrice();
    defer gas_price.deinit();

    return if (base.response > gas_price.response) 0 else gas_price.response - base.response;
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(
    self: *IPC,
    call_object: EthCall,
    base_fee_per_gas: ?Gwei,
) (BasicRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!EstimateFeeReturn {
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
/// The transaction will not be added to the blockchain.
/// Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
/// for a variety of reasons including EVM mechanics and node performance.
///
/// RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)
pub fn estimateGas(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(Gwei) {
    return self.sendEthCallRequest(Gwei, call_object, opts, .eth_estimateGas);
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(
    self: *IPC,
    base_fee_per_gas: ?Gwei,
) (BasicRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!Gwei {
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
pub fn estimateMaxFeePerGas(self: *IPC) BasicRequestErrors!RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_maxPriorityFeePerGas);
}
/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(
    self: *IPC,
    blockCount: u64,
    newest_block: BlockNumberRequest,
    reward_percentil: ?[]const f64,
) BasicRequestErrors!RPCResponse(FeeHistory) {
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
pub fn getAccounts(self: *IPC) BasicRequestErrors!RPCResponse([]const Address) {
    return self.sendBasicRequest([]const Address, .eth_accounts);
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *IPC, opts: BalanceRequest) BasicRequestErrors!RPCResponse(Wei) {
    return self.sendAddressRequest(Wei, opts, .eth_getBalance);
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *IPC, opts: BalanceRequest) BasicRequestErrors!RPCResponse(u64) {
    return self.sendAddressRequest(u64, opts, .eth_getTransactionCount);
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHash(self: *IPC, opts: BlockHashRequest) (BasicRequestErrors || error{InvalidBlockHash})!RPCResponse(Block) {
    return self.getBlockByHashType(Block, opts);
}
/// Returns information about a block by hash.
///
/// Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)
pub fn getBlockByHashType(
    self: *IPC,
    comptime T: type,
    opts: BlockHashRequest,
) (BasicRequestErrors || error{InvalidBlockHash})!RPCResponse(T) {
    const include = opts.include_transaction_objects orelse false;

    const request: EthereumRequest(struct { Hash, bool }) = .{
        .params = .{ opts.block_hash, include },
        .method = .eth_getBlockByHash,
        .id = @intFromEnum(self.network_config.chain_id),
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
pub fn getBlockByNumber(self: *IPC, opts: BlockRequest) (BasicRequestErrors || error{InvalidBlockNumber})!RPCResponse(Block) {
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
pub fn getBlockByNumberType(
    self: *IPC,
    comptime T: type,
    opts: BlockRequest,
) (BasicRequestErrors || error{InvalidBlockNumber})!RPCResponse(T) {
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
pub fn getBlockNumber(self: *IPC) BasicRequestErrors!RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_blockNumber);
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *IPC, block_hash: Hash) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *IPC, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *IPC) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBasicRequest(usize, .eth_chainId);
}
/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *IPC) BasicRequestErrors!RPCResponse([]const u8) {
    return self.sendBasicRequest([]const u8, .web3_clientVersion);
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *IPC, opts: BalanceRequest) BasicRequestErrors!RPCResponse(Hex) {
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
pub fn getFilterOrLogChanges(
    self: *IPC,
    filter_id: u128,
    method: EthereumRpcMethods,
) (BasicRequestErrors || error{ InvalidFilterId, InvalidRpcMethod })!RPCResponse(Logs) {
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
pub fn getGasPrice(self: *IPC) BasicRequestErrors!RPCResponse(Gwei) {
    return self.sendBasicRequest(Gwei, .eth_gasPrice);
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(
    self: *IPC,
    opts: LogRequest,
    tag: ?BalanceBlockTag,
) (BasicRequestErrors || error{InvalidLogRequestParams})!RPCResponse(Logs) {
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
/// Parses the `Value` in the sub-channel as a log event
pub fn getLogsSubEvent(self: *IPC) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Log)) {
    return self.parseSubscriptionEvent(Log);
}
/// Parses the `Value` in the sub-channel as a new heads block event
pub fn getNewHeadsBlockSubEvent(self: *IPC) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Block)) {
    return self.parseSubscriptionEvent(Block);
}
/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *IPC) BasicRequestErrors!RPCResponse(bool) {
    return self.sendBasicRequest(bool, .net_listening);
}
/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *IPC) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_peerCount);
}
/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *IPC) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBasicRequest(usize, .net_version);
}
/// Parses the `Value` in the sub-channel as a pending transaction hash event
pub fn getPendingTransactionsSubEvent(self: *IPC) BasicRequestErrors!RPCResponse(EthereumSubscribeResponse(Hash)) {
    return self.parseSubscriptionEvent(Hash);
}
/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(
    self: *IPC,
    opts: ProofRequest,
    tag: ?ProofBlockTag,
) (BasicRequestErrors || error{ExpectBlockNumberOrTag})!RPCResponse(ProofResult) {
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
pub fn getProtocolVersion(self: *IPC) BasicRequestErrors!RPCResponse(u64) {
    return self.sendBasicRequest(u64, .eth_protocolVersion);
}
/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(self: *IPC, tx_hash: Hash) BasicRequestErrors!RPCResponse(Hex) {
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
///
/// RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)
pub fn getSha3Hash(self: *IPC, message: []const u8) BasicRequestErrors!RPCResponse(Hash) {
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{message},
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
pub fn getStorage(self: *IPC, address: Address, storage_key: Hash, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(Hash) {
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
pub fn getSyncStatus(self: *IPC) ?RPCResponse(SyncProgress) {
    return self.sendBasicRequest(SyncProgress, .eth_syncing) catch null;
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(
    self: *IPC,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction) {
    return self.getTransactionByBlockHashAndIndexType(Transaction, block_hash, index);
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndexType(
    self: *IPC,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T) {
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
/// Returns information about a transaction by block number and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndex(
    self: *IPC,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction) {
    return self.getTransactionByBlockNumberAndIndexType(Transaction, opts, index);
}
/// Returns information about a transaction by block number and transaction index position.
///
/// Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndexType(
    self: *IPC,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T) {
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
pub fn getTransactionByHash(self: *IPC, transaction_hash: Hash) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction) {
    return self.getTransactionByHashType(Transaction, transaction_hash);
}
/// Returns the information about a transaction requested by transaction hash.
///
/// Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHashType(
    self: *IPC,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T) {
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
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(
    self: *IPC,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(TransactionReceipt) {
    return self.getTransactionReceiptType(TransactionReceipt, transaction_hash);
}
/// Returns the receipt of a transaction by transaction hash.
///
/// Use this if the provided receipt type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceiptType(
    self: *IPC,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(TransactionReceipt) {
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
/// The result is an object with two fields pending and queued.
/// Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.
/// These batches themselves are maps associating nonces with actual transactions.
///
/// RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContent(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolContent) {
    return self.sendBasicRequest(TxPoolContent, .txpool_content);
}
/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(self: *IPC, from: Address) BasicRequestErrors!RPCResponse([]const PoolTransactionByNonce) {
    const request: EthereumRequest(struct { Address }) = .{
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
/// as well as the ones that are being scheduled for future execution only.
/// This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.
///
/// RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolInspectStatus(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolInspect) {
    return self.sendBasicRequest(TxPoolInspect, .txpool_inspect);
}
/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolStatus) {
    return self.sendBasicRequest(TxPoolStatus, .txpool_status);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *IPC, block_hash: Hash, index: usize) (BasicRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(Block) {
    return self.getUncleByBlockHashAndIndexType(Block, block_hash, index);
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndexType(
    self: *IPC,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(T) {
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
pub fn getUncleByBlockNumberAndIndex(
    self: *IPC,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(Block) {
    return self.getUncleByBlockNumberAndIndexType(Block, opts, index);
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndexType(
    self: *IPC,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(T) {
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
pub fn getUncleCountByBlockHash(self: *IPC, block_hash: Hash) BasicRequestErrors!RPCResponse(usize) {
    return self.sendBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *IPC, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(usize) {
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
    self: *IPC,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) Multicall(.ipc).Error!AbiDecoded([]const Result) {
    var multicall_caller = try Multicall(.ipc).init(self);

    return multicall_caller.multicall3(targets, function_arguments, allow_failure);
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *IPC) BasicRequestErrors!RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newBlockFilter);
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) BasicRequestErrors!RPCResponse(u128) {
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
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *IPC) BasicRequestErrors!RPCResponse(u128) {
    return self.sendBasicRequest(u128, .eth_newPendingTransactionFilter);
}
/// Creates a read loop to read the socket messages.
/// If a message is too long it will double the buffer size to read the message.
pub fn readLoop(self: *IPC) ReadLoopErrors!void {
    while (!@atomicLoad(bool, &self.ipc_reader.closed, .acquire)) {
        const message = self.ipc_reader.readMessage() catch |err| switch (err) {
            error.Closed,
            error.ConnectionResetByPeer,
            error.BrokenPipe,
            error.NotOpenForReading,
            => return error.Closed,
            else => return,
        };

        ipclog.debug("Got message: {s}", .{message});

        const parsed = self.parseRPCEvent(message) catch {
            if (self.onError) |onError| {
                onError(message) catch return error.UnexpectedError;
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
            onEvent(parsed) catch return error.UnexpectedError;
        }

        if (parsed.value.object.getKey("params") != null) {
            self.sub_channel.put(parsed);
            continue;
        }

        self.rpc_channel.push(parsed);
    }
}
/// Function prepared to start the read loop in a seperate thread.
pub fn readLoopOwnedThread(self: *IPC) void {
    pipe.maybeIgnoreSigpipe();

    self.readLoop() catch |err| {
        ipclog.debug("Read loop reported error: {s}", .{@errorName(err)});
        return;
    };
}
/// Parses a subscription event `Value` into `T`.
/// Usefull for events that currently zabi doesn't have custom support.
pub fn parseSubscriptionEvent(self: *IPC, comptime T: type) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(T)) {
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
pub fn sendEthCall(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) BasicRequestErrors!RPCResponse(Hex) {
    return self.sendEthCallRequest(Hex, call_object, opts, .eth_call);
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *IPC, serialized_tx: Hex) BasicRequestErrors!RPCResponse(Hash) {
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
/// Writes message to websocket server and parses the reponse from it.
/// This blocks until it gets the response back from the server.
pub fn sendRpcRequest(self: *IPC, comptime T: type, message: []u8) SendRpcRequestErrors!RPCResponse(T) {
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.network_config.retries)
            return error.ReachedMaxRetryLimit;

        try self.writeSocketMessage(message);

        const message_value = self.getCurrentRpcEvent();
        errdefer message_value.deinit();

        const parsed = try std.json.parseFromValueLeaky(
            EthereumResponse(T),
            message_value.arena.allocator(),
            message_value.value,
            .{ .allocate = .alloc_always },
        );

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
pub fn uninstallFilter(self: *IPC, id: usize) BasicRequestErrors!RPCResponse(bool) {
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
/// Unsubscribe from different Ethereum event types with a regular RPC call
/// with eth_unsubscribe as the method and the subscriptionId as the first parameter.
///
/// RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)
pub fn unsubscribe(self: *IPC, sub_id: u128) BasicRequestErrors!RPCResponse(bool) {
    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{sub_id},
        .method = .eth_unsubscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(bool, buf_writter.getWritten());
}
/// Emits new blocks that are added to the blockchain.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
pub fn watchNewBlocks(self: *IPC) BasicRequestErrors!RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newHeads},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Emits logs attached to a new block that match certain topic filters and address.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)
pub fn watchLogs(self: *IPC, opts: WatchLogsRequest) BasicRequestErrors!RPCResponse(u128) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const request: EthereumRequest(struct { Subscriptions, WatchLogsRequest }) = .{
        .params = .{ .logs, opts },
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
    };

    try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());

    return self.sendRpcRequest(u128, buf_writter.getWritten());
}
/// Emits transaction hashes that are sent to the network and marked as "pending".
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)
pub fn watchTransactions(self: *IPC) BasicRequestErrors!RPCResponse(u128) {
    const request: EthereumRequest(struct { Subscriptions }) = .{
        .params = .{.newPendingTransactions},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
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
pub fn watchWebsocketEvent(self: *IPC, method: []const u8) BasicRequestErrors!RPCResponse(u128) {
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{method},
        .method = .eth_subscribe,
        .id = @intFromEnum(self.network_config.chain_id),
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
pub fn waitForTransactionReceipt(self: *IPC, tx_hash: Hash, confirmations: u8) (BasicRequestErrors || ParseFromValueError || error{
    TransactionNotFound,
    TransactionReceiptNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
    InvalidBlockNumber,
})!RPCResponse(TransactionReceipt) {
    return self.waitForTransactionReceiptType(TransactionReceipt, tx_hash, confirmations);
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
/// and you know exactly the shape that the data will be in.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceiptType(self: *IPC, comptime T: type, tx_hash: Hash, confirmations: u8) (BasicRequestErrors || ParseFromValueError || error{
    TransactionReceiptNotFound,
    TransactionNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
    InvalidBlockNumber,
})!RPCResponse(T) {
    var tx: ?RPCResponse(Transaction) = null;
    defer if (tx) |t| t.deinit();

    var block_request = try self.getBlockNumber();
    defer block_request.deinit();

    var block_number = block_request.response;

    var receipt: ?RPCResponse(T) = self.getTransactionReceiptType(T, tx_hash) catch |err| switch (err) {
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
        if (retries - valid_confirmations > self.network_config.retries)
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
                std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
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
            std.time.sleep(std.time.ns_per_ms * self.network_config.pooling_interval);
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
fn handleErrorEvent(self: *IPC, error_event: EthereumErrorResponse, retries: usize) EthereumZigErrors!void {
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
fn parseRPCEvent(self: *IPC, request: []const u8) ParseError(Scanner)!JsonParsed(Value) {
    const parsed = std.json.parseFromSlice(Value, self.allocator, request, .{ .allocate = .alloc_always }) catch |err| {
        ipclog.debug("Failed to parse request: {s}", .{request});

        return err;
    };

    return parsed;
}
/// Sends requests with empty params.
fn sendBasicRequest(self: *IPC, comptime T: type, method: EthereumRpcMethods) BasicRequestErrors!RPCResponse(T) {
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

/// Sends specific block_number requests.
fn sendBlockNumberRequest(self: *IPC, opts: BlockNumberRequest, method: EthereumRpcMethods) BasicRequestErrors!RPCResponse(usize) {
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
fn sendBlockHashRequest(self: *IPC, block_hash: Hash, method: EthereumRpcMethods) BasicRequestErrors!RPCResponse(usize) {
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
/// Sends request specific for addresses.
fn sendAddressRequest(self: *IPC, comptime T: type, opts: BalanceRequest, method: EthereumRpcMethods) BasicRequestErrors!RPCResponse(T) {
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
/// Sends eth_call request
fn sendEthCallRequest(self: *IPC, comptime T: type, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) BasicRequestErrors!RPCResponse(T) {
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
