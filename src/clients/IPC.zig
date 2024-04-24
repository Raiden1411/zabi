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
const ws = @import("ws");

const assert = std.debug.assert;

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
const Channel = @import("../utils/channel.zig").Channel;
const EthCall = transaction.EthCall;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumEvents = types.EthereumEvents;
const EthereumResponse = types.EthereumResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcEvents = types.EthereumRpcEvents;
const EthereumRpcMethods = types.EthereumRpcMethods;
const EthereumRpcResponse = types.EthereumRpcResponse;
const EthereumSubscribeEvents = types.EthereumSubscribeEvents;
const EthereumZigErrors = types.EthereumZigErrors;
const EstimateFeeReturn = transaction.EstimateFeeReturn;
const FeeHistory = transaction.FeeHistory;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const IpcServer = @import("../tests/clients/ipc_server.zig");
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
const Stream = std.net.Stream;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const Tuple = std.meta.Tuple;
const TxPoolContent = txpool.TxPoolContent;
const TxPoolInspect = txpool.TxPoolInspect;
const TxPoolStatus = txpool.TxPoolStatus;
const Uri = std.Uri;
const WatchLogsRequest = log.WatchLogsRequest;
const WebsocketSubscriptions = types.WebsocketSubscriptions;
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

pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// The path for the IPC path
    path: []const u8,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: RPCResponse(EthereumEvents)) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
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
sub_channel: *Channel(RPCResponse(EthereumSubscribeEvents)),
/// Channel used to communicate between threads on rpc events.
rpc_channel: *Channel(RPCResponse(EthereumRpcEvents)),
/// Mutex to manage locks between threads
mutex: Mutex = .{},
/// Callback function for when the connection is closed.
onClose: ?*const fn () void,
/// Callback function that will run once a socket event is parsed
onEvent: ?*const fn (args: RPCResponse(EthereumEvents)) anyerror!void,
/// Callback function that will run once a error is parsed.
onError: ?*const fn (args: []const u8) anyerror!void,
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// Retry count for failed connections or requests.
retries: u8,
/// The IPC net stream to read and write requests.
stream: Stream,

/// Starts the IPC client and create the connection.
/// This will also start the read loop in a seperate thread.
pub fn init(self: *IPC, opts: InitOptions) !void {
    const rpc_channel = try opts.allocator.create(Channel(RPCResponse(EthereumRpcEvents)));
    errdefer opts.allocator.destroy(rpc_channel);

    const sub_channel = try opts.allocator.create(Channel(RPCResponse(EthereumSubscribeEvents)));
    errdefer opts.allocator.destroy(sub_channel);

    const chain_id: Chains = opts.chain_id orelse .ethereum;

    self.* = .{
        .allocator = opts.allocator,
        .base_fee_multiplier = opts.base_fee_multiplier,
        .chain_id = @intFromEnum(chain_id),
        .onClose = opts.onClose,
        .onError = opts.onError,
        .onEvent = opts.onEvent,
        .pooling_interval = opts.pooling_interval,
        .retries = opts.retries,
        .rpc_channel = rpc_channel,
        .sub_channel = sub_channel,
        .stream = undefined,
    };

    self.rpc_channel.* = Channel(RPCResponse(EthereumRpcEvents)).init(self.allocator);
    self.sub_channel.* = Channel(RPCResponse(EthereumSubscribeEvents)).init(self.allocator);
    errdefer {
        self.rpc_channel.deinit();
        self.sub_channel.deinit();
    }

    const stream = try self.connect(opts.path);
    self.stream = stream;

    const thread = try std.Thread.spawn(.{}, readLoopOwnedThread, .{self});
    thread.detach();
}
/// Clears memory, closes the stream and destroys any
/// previously created pointers.
///
/// All future calls will deadlock.
pub fn deinit(self: *IPC) void {
    self.mutex.lock();

    self.stream.close();
    while (self.sub_channel.getOrNull()) |response| {
        response.deinit();
    }

    while (self.rpc_channel.getOrNull()) |response| {
        response.deinit();
    }

    self.rpc_channel.deinit();
    self.sub_channel.deinit();

    self.allocator.destroy(self.rpc_channel);
    self.allocator.destroy(self.sub_channel);

    self.* = undefined;
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
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_blobBaseFee,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(Gwei, buf_writter.getWritten());
}
/// Create an accessList of addresses and storageKeys for an transaction to access
///
/// RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)
pub fn createAccessList(self: *IPC, call_object: EthCall, opts: BlockNumberRequest) !RPCResponse(AccessListResult) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    self.mutex.lock();

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = .eth_createAccessList,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = .eth_createAccessList,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const list_message = self.rpc_channel.get();
        errdefer list_message.deinit();

        switch (list_message.response) {
            .access_list => |list_event| return .{ .arena = list_message.arena, .response = list_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a access_list.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
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
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    self.mutex.lock();

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = .eth_estimateGas,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = .eth_estimateGas,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }
    self.mutex.unlock();

    return self.handleNumberEvent(Gwei, buf_writter.getWritten());
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
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_maxPriorityFeePerGas,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(Gwei, buf_writter.getWritten());
}
/// Returns historical gas information, allowing you to track trends over time.
///
/// RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)
pub fn feeHistory(self: *IPC, blockCount: u64, newest_block: BlockNumberRequest, reward_percentil: ?[]const f64) !RPCResponse(FeeHistory) {
    const tag: BalanceBlockTag = newest_block.tag orelse .latest;
    self.mutex.lock();

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

    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const fee_message = self.rpc_channel.get();
        errdefer fee_message.deinit();

        switch (fee_message.response) {
            .fee_history => |fee_event| return .{ .arena = fee_message.arena, .response = fee_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a fee_history event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns a list of addresses owned by client.
///
/// RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)
pub fn getAccounts(self: *IPC) !RPCResponse([]const Address) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_accounts,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const accounts_message = self.rpc_channel.get();
        errdefer accounts_message.deinit();

        switch (accounts_message.response) {
            .accounts_event => |accounts_event| return .{ .arena = accounts_message.arena, .response = accounts_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a accounts_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *IPC, opts: BalanceRequest) !RPCResponse(Wei) {
    self.mutex.lock();

    const tag: BalanceBlockTag = opts.tag orelse .latest;
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = .eth_getBalance,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = .eth_getBalance,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }
    self.mutex.unlock();

    return self.handleNumberEvent(Wei, buf_writter.getWritten());
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *IPC, opts: BalanceRequest) !RPCResponse(u64) {
    self.mutex.lock();

    const tag: BalanceBlockTag = opts.tag orelse .latest;
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = .eth_getTransactionCount,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = .eth_getTransactionCount,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }
    self.mutex.unlock();

    return self.handleNumberEvent(Gwei, buf_writter.getWritten());
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockByHash(self: *IPC, opts: BlockHashRequest) !RPCResponse(Block) {
    const include = opts.include_transaction_objects orelse false;
    self.mutex.lock();

    const request: EthereumRequest(struct { Hash, bool }) = .{
        .params = .{ opts.block_hash, include },
        .method = .eth_getBlockByHash,
        .id = self.chain_id,
    };

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const block_message = self.rpc_channel.get();
        errdefer block_message.deinit();

        switch (block_message.response) {
            .block_event => |block_event| return .{ .arena = block_message.arena, .response = block_event.result },
            .null_event => return error.InvalidBlockHash,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a block_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockByNumber(self: *IPC, opts: BlockRequest) !RPCResponse(Block) {
    const tag: block.BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;
    self.mutex.lock();

    var request_buffer: [2 * 1024]u8 = undefined;
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

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const block_message = self.rpc_channel.get();
        errdefer block_message.deinit();

        switch (block_message.response) {
            .block_event => |block_event| return .{ .arena = block_message.arena, .response = block_event.result },
            .null_event => return error.InvalidBlockNumber,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a block_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockNumber(self: *IPC) !RPCResponse(u64) {
    self.mutex.lock();
    defer self.mutex.unlock();

    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .eth_blockNumber,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(u64, buf_writter.getWritten());
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *IPC, block_hash: Hash) !RPCResponse(u64) {
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{block_hash},
        .method = .eth_getBlockTransactionCountByHash,
        .id = self.chain_id,
    };
    self.mutex.lock();

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    return self.handleNumberEvent(u64, buf_writter.getWritten());
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *IPC, opts: BlockNumberRequest) !RPCResponse(u64) {
    const tag: BalanceBlockTag = opts.tag orelse .latest;
    self.mutex.lock();

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64 }) = .{
            .params = .{number},
            .method = .eth_getBlockTransactionCountByNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag }) = .{
            .params = .{tag},
            .method = .eth_getBlockTransactionCountByNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }
    self.mutex.unlock();

    return self.handleNumberEvent(u64, buf_writter.getWritten());
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *IPC) !RPCResponse(usize) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_chainId,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const chain_message = self.rpc_channel.get();
        errdefer chain_message.deinit();

        switch (chain_message.response) {
            .number_event => |chain| {
                const chain_id: usize = @truncate(chain.result);

                if (chain_id != self.chain_id)
                    return error.InvalidChainId;

                return .{ .arena = chain_message.arena, .response = chain_id };
            },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a number_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the node's client version
///
/// RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)
pub fn getClientVersion(self: *IPC) !RPCResponse([]const u8) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .web3_clientVersion,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const string_message = self.rpc_channel.get();
        errdefer string_message.deinit();

        switch (string_message.response) {
            .hex_event => |hex_event| return .{ .arena = string_message.arena, .response = hex_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *IPC, opts: BalanceRequest) !RPCResponse(Hex) {
    self.mutex.lock();

    const tag: BalanceBlockTag = opts.tag orelse .latest;
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { Address, u64 }) = .{
            .params = .{ opts.address, number },
            .method = .eth_getCode,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { Address, BalanceBlockTag }) = .{
            .params = .{ opts.address, tag },
            .method = .eth_getCode,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hex_message = self.rpc_channel.get();
        errdefer hex_message.deinit();

        switch (hex_message.response) {
            .hex_event => |hex| return .{ .arena = hex_message.arena, .response = hex.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Get the first event of the rpc channel.
/// Only call this if you are sure that the channel has messages.
/// Otherwise this will run in a infinite loop.
pub fn getCurrentRpcEvent(self: *IPC) RPCResponse(EthereumRpcEvents) {
    return self.rpc_channel.get();
}
/// Get the first event of the subscription channel.
/// Only call this if you are sure that the channel has messages.
/// Otherwise this will run in a infinite loop.
pub fn getCurrentSubscriptionEvent(self: *IPC) RPCResponse(EthereumSubscribeEvents) {
    return self.sub_channel.get();
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *IPC, filter_id: u128, method: EthereumRpcMethods) !RPCResponse(Logs) {
    switch (method) {
        .eth_getFilterLogs, .eth_getFilterChanges => {},
        else => return error.InvalidRpcMethod,
    }

    self.mutex.lock();

    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{filter_id},
        .method = method,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const logs_message = self.rpc_channel.get();
        errdefer logs_message.deinit();

        switch (logs_message.response) {
            .logs_event => |logs_event| return .{ .arena = logs_message.arena, .response = logs_event.result },
            .null_event => return error.InvalidFilterId,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a logs_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *IPC) !RPCResponse(Gwei) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_gasPrice,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(Gwei, buf_writter.getWritten());
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(Logs) {
    self.mutex.lock();

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

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const logs_message = self.rpc_channel.get();
        errdefer logs_message.deinit();

        switch (logs_message.response) {
            .logs_event => |logs_event| return .{ .arena = logs_message.arena, .response = logs_event.result },
            .null_event => return error.InvalidFilterId,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a logs_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns true if client is actively listening for network connections.
///
/// RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)
pub fn getNetworkListenStatus(self: *IPC) !RPCResponse(bool) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .net_listening,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const bool_message = self.rpc_channel.get();
        errdefer bool_message.deinit();

        switch (bool_message.response) {
            .bool_event => |bool_event| return .{ .arena = bool_message.arena, .response = bool_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a bool_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns number of peers currently connected to the client.
///
/// RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)
pub fn getNetworkPeerCount(self: *IPC) !RPCResponse(usize) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .net_peerCount,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    return self.handleNumberEvent(usize, buf_writter.getWritten());
}
/// Returns the current network id.
///
/// RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)
pub fn getNetworkVersionId(self: *IPC) !RPCResponse(usize) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .net_version,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    return self.handleNumberEvent(usize, buf_writter.getWritten());
}
/// Returns the account and storage values, including the Merkle proof, of the specified account
///
/// RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)
pub fn getProof(self: *IPC, opts: ProofRequest, tag: ?ProofBlockTag) !RPCResponse(ProofResult) {
    self.mutex.lock();

    var request_buffer: [4 * 1024]u8 = undefined;
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

    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const proof_message = self.rpc_channel.get();
        errdefer proof_message.deinit();

        switch (proof_message.response) {
            .proof_event => |proof_event| return .{ .arena = proof_message.arena, .response = proof_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a proof_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the current Ethereum protocol version.
///
/// RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)
pub fn getProtocolVersion(self: *IPC) !RPCResponse(u64) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .eth_protocolVersion,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    return self.handleNumberEvent(u64, buf_writter.getWritten());
}
/// Returns the raw transaction data as a hexadecimal string for a given transaction hash
///
/// RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)
pub fn getRawTransactionByHash(self: *IPC, tx_hash: Hash) !RPCResponse(Hex) {
    self.mutex.lock();
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{tx_hash},
        .method = .eth_getRawTransactionByHash,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hex_message = self.rpc_channel.get();
        errdefer hex_message.deinit();

        switch (hex_message.response) {
            .hex_event => |hex| return .{ .arena = hex_message.arena, .response = hex.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hex_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the Keccak256 hash of the given message.
///
/// RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)
pub fn getSha3Hash(self: *IPC, message: []const u8) !RPCResponse(Hash) {
    self.mutex.lock();
    const request: EthereumRequest(struct { []const u8 }) = .{
        .params = .{message},
        .method = .web3_sha3,
        .id = self.chain_id,
    };

    var request_buffer: [4096]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hash_message = self.rpc_channel.get();
        errdefer hash_message.deinit();

        switch (hash_message.response) {
            .hash_event => |hash| return .{ .arena = hash_message.arena, .response = hash.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hash_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the value from a storage position at a given address.
///
/// RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)
pub fn getStorage(self: *IPC, address: Address, storage_key: Hash, opts: BlockNumberRequest) !RPCResponse(Hash) {
    self.mutex.lock();

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const tag: BalanceBlockTag = opts.tag orelse .latest;

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

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hash_message = self.rpc_channel.get();
        errdefer hash_message.deinit();

        switch (hash_message.response) {
            .hash_event => |hash| return .{ .arena = hash_message.arena, .response = hash.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hash_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns null if the node has finished syncing. Otherwise it will return
/// the sync progress.
///
/// RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)
pub fn getSyncStatus(self: *IPC) !?RPCResponse(SyncProgress) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&.{})) = .{
        .params = .{},
        .method = .eth_syncing,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const bool_message = self.rpc_channel.get();
        errdefer bool_message.deinit();

        switch (bool_message.response) {
            .bool_event => {
                defer bool_message.deinit();
                return null;
            },
            .sync_event => |sync_status| return .{ .arena = bool_message.arena, .response = sync_status.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a bool_event or sync_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *IPC, block_hash: Hash, index: usize) !RPCResponse(Transaction) {
    self.mutex.lock();

    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getTransactionByBlockHashAndIndex,
        .id = self.chain_id,
    };

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const transaction_message = self.rpc_channel.get();
        errdefer transaction_message.deinit();

        switch (transaction_message.response) {
            .transaction_event => |tx_event| return .{ .arena = transaction_message.arena, .response = tx_event.result },
            .null_event => return error.TransactionNotFound,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a transaction by block number and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndex(self: *IPC, opts: BlockNumberRequest, index: usize) !RPCResponse(Transaction) {
    self.mutex.lock();
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
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

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const transaction_message = self.rpc_channel.get();
        errdefer transaction_message.deinit();

        switch (transaction_message.response) {
            .transaction_event => |tx_event| return .{ .arena = transaction_message.arena, .response = tx_event.result },
            .null_event => return error.TransactionNotFound,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the information about a transaction requested by transaction hash.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHash(self: *IPC, transaction_hash: Hash) !RPCResponse(Transaction) {
    self.mutex.lock();

    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionByHash,
        .id = self.chain_id,
    };

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const transaction_message = self.rpc_channel.get();
        errdefer transaction_message.deinit();

        switch (transaction_message.response) {
            .transaction_event => |tx_event| return .{ .arena = transaction_message.arena, .response = tx_event.result },
            .null_event => return error.TransactionNotFound,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(self: *IPC, transaction_hash: Hash) !RPCResponse(TransactionReceipt) {
    self.mutex.lock();
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{transaction_hash},
        .method = .eth_getTransactionReceipt,
        .id = self.chain_id,
    };

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());
        const receipt_message = self.rpc_channel.get();
        errdefer receipt_message.deinit();

        switch (receipt_message.response) {
            .receipt_event => |receipt_event| return .{ .arena = receipt_message.arena, .response = receipt_event.result },
            .null_event => return error.TransactionReceiptNotFound,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a receipt_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
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
    self.mutex.lock();
    const request: EthereumRequest(struct {}) = .{
        .params = .{},
        .method = .txpool_content,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());
        const txpool_content_message = self.rpc_channel.get();
        errdefer txpool_content_message.deinit();

        switch (txpool_content_message.response) {
            .txpool_content_event => |txpool_content| return .{ .arena = txpool_content_message.arena, .response = txpool_content.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a txpool_content_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Retrieves the transactions contained within the txpool,
/// returning pending as well as queued transactions of this address, grouped by nonce
///
/// RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolContentFrom(self: *IPC, from: Address) !RPCResponse([]const PoolTransactionByNonce) {
    self.mutex.lock();
    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{from},
        .method = .txpool_contentFrom,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());
        const txpool_content_message = self.rpc_channel.get();
        errdefer txpool_content_message.deinit();

        switch (txpool_content_message.response) {
            .txpool_content_from_event => |txpool_content_from| return .{ .arena = txpool_content_message.arena, .response = txpool_content_from.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a txpool_content_from_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
/// This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.
///
/// RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolInspectStatus(self: *IPC) !RPCResponse(TxPoolInspect) {
    self.mutex.lock();
    const request: EthereumRequest(struct {}) = .{
        .params = .{},
        .method = .txpool_inspect,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());
        const txpool_inspect_message = self.rpc_channel.get();
        errdefer txpool_inspect_message.deinit();

        switch (txpool_inspect_message.response) {
            .txpool_inspect_event => |txpool_inspect| return .{ .arena = txpool_inspect_message.arena, .response = txpool_inspect.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a txpool_inspect_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
/// as well as the ones that are being scheduled for future execution only.
///
/// RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)
pub fn getTxPoolStatus(self: *IPC) !RPCResponse(TxPoolStatus) {
    self.mutex.lock();
    const request: EthereumRequest(struct {}) = .{
        .params = .{},
        .method = .txpool_status,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());
    self.mutex.unlock();

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());
        const txpool_status_message = self.rpc_channel.get();
        errdefer txpool_status_message.deinit();

        switch (txpool_status_message.response) {
            .txpool_status_event => |txpool_status| return .{ .arena = txpool_status_message.arena, .response = txpool_status.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a txpool_status_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *IPC, block_hash: Hash, index: usize) !RPCResponse(Block) {
    self.mutex.lock();
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const request: EthereumRequest(struct { Hash, usize }) = .{
        .params = .{ block_hash, index },
        .method = .eth_getUncleByBlockHashAndIndex,
        .id = self.chain_id,
    };

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const block_message = self.rpc_channel.get();
        errdefer block_message.deinit();

        switch (block_message.response) {
            .block_event => |block_event| return .{ .arena = block_message.arena, .response = block_event.result },
            .null_event => return error.InvalidBlockRequest,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a block_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndex(self: *IPC, opts: BlockNumberRequest, index: usize) !RPCResponse(Block) {
    self.mutex.lock();
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const tag: BalanceBlockTag = opts.tag orelse .latest;

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

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const block_message = self.rpc_channel.get();
        errdefer block_message.deinit();

        switch (block_message.response) {
            .block_event => |block_event| return .{ .arena = block_message.arena, .response = block_event.result },
            .null_event => return error.InvalidBlockRequest,
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a block_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of uncles in a block from a block matching the given block hash.
///
/// RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)
pub fn getUncleCountByBlockHash(self: *IPC, block_hash: Hash) !RPCResponse(usize) {
    self.mutex.lock();

    const request: EthereumRequest(struct { Hash }) = .{
        .params = .{block_hash},
        .method = .eth_getUncleCountByBlockHash,
        .id = self.chain_id,
    };

    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();

    return self.handleNumberEvent(usize, buf_writter.getWritten());
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *IPC, opts: BlockNumberRequest) !RPCResponse(usize) {
    self.mutex.lock();
    var request_buffer: [2 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const tag: BalanceBlockTag = opts.tag orelse .latest;
    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { u64 }) = .{
            .params = .{number},
            .method = .eth_getUncleCountByBlockNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { BalanceBlockTag }) = .{
            .params = .{tag},
            .method = .eth_getUncleCountByBlockNumber,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{}, buf_writter.writer());
    }

    self.mutex.unlock();

    return self.handleNumberEvent(usize, buf_writter.getWritten());
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *IPC) !RPCResponse(u128) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_newBlockFilter,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(u128, buf_writter.getWritten());
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) !RPCResponse(u128) {
    self.mutex.lock();
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

    self.mutex.unlock();
    ipclog.debug("FOOOO: {s}", .{buf_writter.getWritten()});

    return self.handleNumberEvent(u128, buf_writter.getWritten());
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *IPC) !RPCResponse(u128) {
    self.mutex.lock();
    const request: EthereumRequest(Tuple(&[_]type{})) = .{
        .params = .{},
        .method = .eth_newPendingTransactionFilter,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);
    self.mutex.unlock();

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(u128, buf_writter.getWritten());
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
    self.mutex.lock();
    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const tag: BalanceBlockTag = opts.tag orelse .latest;
    if (opts.block_number) |number| {
        const request: EthereumRequest(struct { EthCall, u64 }) = .{
            .params = .{ call_object, number },
            .method = .eth_call,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    } else {
        const request: EthereumRequest(struct { EthCall, BalanceBlockTag }) = .{
            .params = .{ call_object, tag },
            .method = .eth_call,
            .id = self.chain_id,
        };

        try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());
    }

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hash_message = self.rpc_channel.get();
        errdefer hash_message.deinit();

        switch (hash_message.response) {
            .hex_event => |hex| return .{ .arena = hash_message.arena, .response = hex.result },
            .hash_event => |hash| return .{ .arena = hash_message.arena, .response = std.mem.bytesAsSlice(u8, @constCast(hash.result[0..])) },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hash_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *IPC, serialized_tx: Hex) !RPCResponse(Hash) {
    self.mutex.lock();

    const request: EthereumRequest(struct { Hex }) = .{
        .params = .{serialized_tx},
        .method = .eth_sendRawTransaction,
        .id = self.chain_id,
    };

    var request_buffer: [8 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const hash_message = self.rpc_channel.get();
        errdefer hash_message.deinit();

        switch (hash_message.response) {
            .hash_event => |hash| return .{ .arena = hash_message.arena, .response = hash.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a hash_event", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstalllFilter(self: *IPC, id: usize) !RPCResponse(bool) {
    self.mutex.lock();
    const request: EthereumRequest(struct { usize }) = .{
        .params = .{id},
        .method = .eth_uninstallFilter,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const bool_message = self.rpc_channel.get();
        errdefer bool_message.deinit();

        switch (bool_message.response) {
            .bool_event => |bool_event| return .{ .arena = bool_message.arena, .response = bool_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a bool_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Unsubscribe from different Ethereum event types with a regular RPC call
/// with eth_unsubscribe as the method and the subscriptionId as the first parameter.
///
/// RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)
pub fn unsubscribe(self: *IPC, sub_id: u128) !RPCResponse(bool) {
    self.mutex.lock();

    const request: EthereumRequest(struct { u128 }) = .{
        .params = .{sub_id},
        .method = .eth_unsubscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    self.mutex.unlock();
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(buf_writter.getWritten());

        const bool_message = self.rpc_channel.get();
        errdefer bool_message.deinit();

        switch (bool_message.response) {
            .bool_event => |bool_event| return .{ .arena = bool_message.arena, .response = bool_event.result },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.debug("Found incorrect event named: {s}. Expected a bool_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates a read loop to read the socket messages.
/// If a message is too long it will double the buffer size to read the message.
///
/// This is thread safe.
pub fn readLoop(self: *IPC) !void {
    var list = std.ArrayList(u8).init(self.allocator);
    errdefer list.deinit();

    while (true) {
        try self.readMessage(list.writer());

        const message = try list.toOwnedSlice();
        defer self.allocator.free(message);

        ipclog.debug("Got message: {s}", .{message});
        const parsed = std.json.parseFromSlice(EthereumEvents, self.allocator, message, .{ .allocate = .alloc_always }) catch |err| {
            ipclog.debug("Failed to parse: {s}. Json error: {s}", .{ message, @errorName(err) });
            const timeout = std.mem.toBytes(std.posix.timeval{
                .tv_sec = @intCast(0),
                .tv_usec = @intCast(1000),
            });
            try std.posix.setsockopt(self.stream.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &timeout);

            return error.FailedToJsonParseRequest;
        };
        errdefer parsed.deinit();

        if (self.onEvent) |onEvent| {
            try onEvent(RPCResponse(EthereumEvents).fromJson(parsed.arena, parsed.value));
        }

        switch (parsed.value) {
            .subscribe_event => |sub_event| self.sub_channel.put(.{ .arena = parsed.arena, .response = sub_event }),
            .rpc_event => |rpc_event| self.rpc_channel.put(.{ .arena = parsed.arena, .response = rpc_event }),
        }
    }
}
/// Function prepared to start the read loop in a seperate thread.
pub fn readLoopOwnedThread(self: *IPC) !void {
    errdefer self.deinit();
    pipe.maybeIgnoreSigpipe();

    self.readLoop() catch |err| {
        ipclog.err("Read loop reported error: {s}", .{@errorName(err)});
        return;
    };
}
/// Emits new blocks that are added to the blockchain.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
pub fn watchNewBlocks(self: *IPC) !RPCResponse(u128) {
    self.mutex.lock();
    defer self.mutex.unlock();

    const request: EthereumRequest(struct { WebsocketSubscriptions }) = .{
        .params = .{.newHeads},
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(u128, buf_writter.getWritten());
}
/// Emits logs attached to a new block that match certain topic filters and address.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)
pub fn watchLogs(self: *IPC, opts: WatchLogsRequest) !RPCResponse(u128) {
    var request_buffer: [4 * 1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    const request: EthereumRequest(struct { WebsocketSubscriptions, WatchLogsRequest }) = .{
        .params = .{ .logs, opts },
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    try std.json.stringify(request, .{ .emit_null_optional_fields = false }, buf_writter.writer());

    return self.handleNumberEvent(u128, buf_writter.getWritten());
}
/// Emits transaction hashes that are sent to the network and marked as "pending".
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)
pub fn watchTransactions(self: *IPC) !RPCResponse(u128) {
    const request: EthereumRequest(struct { WebsocketSubscriptions }) = .{
        .params = .{.newPendingTransactions},
        .method = .eth_subscribe,
        .id = self.chain_id,
    };

    var request_buffer: [1024]u8 = undefined;
    var buf_writter = std.io.fixedBufferStream(&request_buffer);

    try std.json.stringify(request, .{}, buf_writter.writer());

    return self.handleNumberEvent(u128, buf_writter.getWritten());
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

    return self.handleNumberEvent(u128, buf_writter.getWritten());
}
/// Waits until a transaction gets mined and the receipt can be grabbed.
/// This is retry based on either the amount of `confirmations` given.
///
/// If 0 confirmations are given the transaction receipt can be null in case
/// the transaction has not been mined yet. It's recommened to have atleast one confirmation
/// because some nodes might be slower to sync.
///
/// This also supports checking if the transaction was replaced. It will return the
/// replaced transactions receipt in the case it was replaced.
///
/// RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn waitForTransactionReceipt(self: *IPC, tx_hash: Hash, confirmations: u8) !RPCResponse(TransactionReceipt) {
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

        const event = self.sub_channel.get();
        defer event.deinit();

        switch (event.response) {
            .new_heads_event => {},
            else => {
                // Decrements the retries since we didn't get a block subscription
                continue;
            },
        }

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
/// Internal Handler for RPC requests where the expected response
/// is a hex encoded number.
fn handleNumberEvent(self: *IPC, comptime T: type, req_body: []u8) !RPCResponse(T) {
    var retries: u8 = 0;

    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.stream.writeAll(req_body);
        const get_response = self.rpc_channel.get();
        errdefer get_response.deinit();

        switch (get_response.response) {
            .number_event => |event| return .{ .arena = get_response.arena, .response = @as(T, @truncate(event.result)) },
            // Really big numbers might get processed as a [32]u8 array.
            // So we convert it back to a number.
            .hash_event => |event| {
                if (T != u256)
                    return error.NumberToBig;

                const as_number = std.mem.readInt(u256, &event.result, .big);
                return .{ .arena = get_response.arena, .response = as_number };
            },
            .error_event => |error_response| try self.handleErrorEvent(error_response, retries),
            else => |eve| {
                ipclog.err("Found incorrect event named: {s}. Expected a number_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Reads one json message from the socket. The list growth is super
/// linear as it's the safest option to ensure that we grab a just one json
/// message.
///
/// Returns whether or not it was able to read a message.
fn readMessage(self: *IPC, writer: anytype) !void {
    var depth: usize = 0;

    while (true) {
        var result: [1]u8 = undefined;
        const size = try self.stream.read(result[0..]);

        if (size < 1) {
            if (depth == 0)
                return;

            return error.EndOfStream;
        }

        try writer.writeAll(result[0..]);

        switch (result[0]) {
            '{' => depth += 1,
            '}' => depth -= 1,
            else => {},
        }

        // Check if we read a message or not.
        if (depth == 0) {
            return;
        }
    }
}

test "BlockByNumber" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByNumber(.{ .block_number = 10 });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByNumber(.{});
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByNumber(.{ .include_transaction_objects = true });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByNumber(.{ .block_number = 1000000, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockByHash" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByHash(.{ .block_hash = [_]u8{0} ** 32 });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockByHash(.{ .block_hash = [_]u8{0} ** 32, .include_transaction_objects = true });
        defer block_number.deinit();
    }
}

test "BlockTransactionCountByHash" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const block_number = try client.getBlockTransactionCountByHash([_]u8{0} ** 32);
    defer block_number.deinit();
}

test "BlockTransactionCountByNumber" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockTransactionCountByNumber(.{ .block_number = 100101 });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getBlockTransactionCountByNumber(.{});
        defer block_number.deinit();
    }
}

test "AddressNonce" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getAddressTransactionCount(.{ .address = [_]u8{0} ** 20 });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getAddressTransactionCount(.{ .address = [_]u8{0} ** 20, .block_number = 100012 });
        defer block_number.deinit();
    }
}

test "AddressBalance" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getAddressBalance(.{ .address = [_]u8{0} ** 20, .block_number = 100101 });
        defer block_number.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const block_number = try client.getAddressBalance(.{ .address = [_]u8{0} ** 20 });
        defer block_number.deinit();
    }
}

test "BlockNumber" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const block_number = try client.getBlockNumber();
    defer block_number.deinit();
}

test "GetChainId" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    // Since the data is random it's expected to fail.
    try testing.expectError(error.InvalidChainId, client.getChainId());
}

test "GetStorage" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{});
        defer storage.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);
        const storage = try client.getStorage([_]u8{0} ** 20, [_]u8{0} ** 32, .{ .block_number = 101010 });
        defer storage.deinit();
    }
}

test "GetAccounts" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const accounts = try client.getAccounts();
    defer accounts.deinit();
}

test "GetContractCode" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const code = try client.getContractCode(.{ .address = [_]u8{0} ** 20 });
        defer code.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const code = try client.getContractCode(.{ .address = [_]u8{0} ** 20, .block_number = 101010 });
        defer code.deinit();
    }
}

test "GetTransactionByHash" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const tx = try client.getTransactionByHash([_]u8{0} ** 32);
    defer tx.deinit();
}

test "GetReceipt" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const receipt = try client.getTransactionReceipt([_]u8{0} ** 32);
    defer receipt.deinit();
}

test "GetFilter" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterChanges);
        defer filter.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const filter = try client.getFilterOrLogChanges(0, .eth_getFilterLogs);
        defer filter.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);
        try testing.expectError(error.InvalidRpcMethod, client.getFilterOrLogChanges(0, .eth_chainId));
    }
}

test "GetGasPrice" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();

    std.time.sleep(std.time.ns_per_ms * 100);

    const gas = try client.getGasPrice();
    defer gas.deinit();
}

test "GetUncleCountByBlockHash" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const uncle = try client.getUncleCountByBlockHash([_]u8{0} ** 32);
    defer uncle.deinit();
}

test "GetUncleCountByBlockNumber" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const uncle = try client.getUncleCountByBlockNumber(.{});
        defer uncle.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const uncle = try client.getUncleCountByBlockNumber(.{ .block_number = 101010 });
        defer uncle.deinit();
    }
}

test "GetUncleByBlockNumberAndIndex" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const uncle = try client.getUncleByBlockNumberAndIndex(.{}, 0);
        defer uncle.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const uncle = try client.getUncleByBlockNumberAndIndex(.{ .block_number = 101010 }, 0);
        defer uncle.deinit();
    }
}

test "GetUncleByBlockHashAndIndex" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const tx = try client.getUncleByBlockHashAndIndex([_]u8{0} ** 32, 0);
    defer tx.deinit();
}

test "GetTransactionByBlockNumberAndIndex" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const tx = try client.getTransactionByBlockNumberAndIndex(.{}, 0);
        defer tx.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const tx = try client.getTransactionByBlockNumberAndIndex(.{ .block_number = 101010 }, 0);
        defer tx.deinit();
    }
}

test "EstimateGas" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const fee = try client.estimateGas(.{ .london = .{ .gas = 10 } }, .{});
        defer fee.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const fee = try client.estimateGas(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const fee = try client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{});
        defer fee.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const fee = try client.estimateGas(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer fee.deinit();
    }
}

test "CreateAccessList" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const access = try client.createAccessList(.{ .london = .{ .gas = 10 } }, .{});
        defer access.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const access = try client.createAccessList(.{ .london = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer access.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const access = try client.createAccessList(.{ .legacy = .{ .gas = 10 } }, .{});
        defer access.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const access = try client.createAccessList(.{ .legacy = .{ .gas = 10 } }, .{ .block_number = 101010 });
        defer access.deinit();
    }
}

test "GetNetworkPeerCount" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const count = try client.getNetworkPeerCount();
    defer count.deinit();
}

test "GetNetworkVersionId" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const id = try client.getNetworkVersionId();
    defer id.deinit();
}

test "GetNetworkListenStatus" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const status = try client.getNetworkListenStatus();
    defer status.deinit();
}

test "GetSha3Hash" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const hash = try client.getSha3Hash("foobar");
    defer hash.deinit();
}

test "GetClientVersion" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const version = try client.getClientVersion();
    defer version.deinit();
}

test "BlobBaseFee" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const blob = try client.blobBaseFee();
    defer blob.deinit();
}

test "EstimateMaxFeePerGas" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const max = try client.estimateMaxFeePerGas();
    defer max.deinit();
}

test "GetProof" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{}, .blockNumber = 101010 }, null);
        defer proofs.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const proofs = try client.getProof(.{ .address = [_]u8{0} ** 20, .storageKeys = &.{} }, .latest);
        defer proofs.deinit();
    }
}

test "GetLogs" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const logs = try client.getLogs(.{ .toBlock = 101010, .fromBlock = 101010 }, null);
        defer logs.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const logs = try client.getLogs(.{}, .latest);
        defer logs.deinit();
    }
}

test "NewLogFilter" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const logs = try client.newLogFilter(.{}, .latest);
        defer logs.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const logs = try client.newLogFilter(.{ .fromBlock = 101010, .toBlock = 101010 }, null);
        defer logs.deinit();
    }
}

test "NewBlockFilter" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const block_id = try client.newBlockFilter();
    defer block_id.deinit();
}

test "NewPendingTransactionFilter" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const tx_id = try client.newPendingTransactionFilter();
    defer tx_id.deinit();
}

test "UninstalllFilter" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const status = try client.uninstalllFilter(1);
    defer status.deinit();
}

test "GetProtocolVersion" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const version = try client.getProtocolVersion();
    defer version.deinit();
}

test "SyncStatus" {
    var server: IpcServer = undefined;
    defer server.deinit();

    try server.init(testing.allocator, .{});

    var client: IPC = undefined;
    defer client.deinit();

    try client.init(.{
        .allocator = testing.allocator,
        .path = "/tmp/zabi.ipc",
    });

    try server.listenOnceInSeperateThread();
    std.time.sleep(std.time.ns_per_ms * 100);

    const status = try client.getSyncStatus();
    defer if (status) |s| s.deinit();
}

test "FeeHistory" {
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const status = try client.feeHistory(10, .{}, null);
        defer status.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const status = try client.feeHistory(10, .{ .block_number = 101010 }, null);
        defer status.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);

        const status = try client.feeHistory(10, .{}, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
    {
        var server: IpcServer = undefined;
        defer server.deinit();

        try server.init(testing.allocator, .{});

        var client: IPC = undefined;
        defer client.deinit();

        try client.init(.{
            .allocator = testing.allocator,
            .path = "/tmp/zabi.ipc",
        });

        try server.listenOnceInSeperateThread();
        std.time.sleep(std.time.ns_per_ms * 100);
        const status = try client.feeHistory(10, .{ .block_number = 101010 }, &.{ 0.1, 0.2 });
        defer status.deinit();
    }
}
