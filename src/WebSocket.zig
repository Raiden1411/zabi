const block = @import("meta/block.zig");
const meta = @import("meta/meta.zig");
const log = @import("meta/log.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const ws = @import("ws");

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
const Channel = @import("channel.zig").Channel;
const EthCall = transaction.EthCall;
const EthCallHexed = transaction.EthCallHexed;
const ErrorResponse = types.ErrorResponse;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumEvents = types.EthereumEvents;
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

const WebSocketHandler = @This();

const wslog = std.log.scoped(.ws);

pub const WebSocketHandlerErrors = error{ FailedToConnect, UnsupportedSchema, InvalidChainId, FailedToGetReceipt, FailedToUnsubscribe, InvalidFilterId, InvalidEventFound, InvalidBlockRequest, InvalidLogRequest, TransactionNotFound, TransactionReceiptNotFound, InvalidHash, UnexpectedErrorFound, UnableToFetchFeeInfoFromBlock, UnexpectedTooManyRequestError, InvalidInput, InvalidParams, InvalidRequest, InvalidAddress, InvalidBlockHash, InvalidBlockHashOrIndex, InvalidBlockNumberOrIndex, TooManyRequests, MethodNotFound, MethodNotSupported, RpcVersionNotSupported, LimitExceeded, TransactionRejected, ResourceNotFound, ResourceUnavailable, UnexpectedRpcErrorCode, InvalidBlockNumber, ParseError, ReachedMaxRetryLimit } || Allocator.Error || std.fmt.ParseIntError || std.Uri.ParseError;

pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// Fork url for anvil to fork from
    uri: std.Uri,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// Callback function for when the connection is closed.
    onClose: ?*const fn () void = null,
    /// Callback function for everytime an event is parsed.
    onEvent: ?*const fn (args: EthereumEvents) anyerror!void = null,
    /// Callback function for everytime an error is caught.
    onError: ?*const fn (args: []const u8) anyerror!void = null,
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
    retries: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// The base fee multiplier used to estimate the gas fees in a transaction
    base_fee_multiplier: f64 = 1.2,
};

/// Arena used to manage the socket connection
_arena: *ArenaAllocator,
/// The allocator that will manage the connections memory
allocator: std.mem.Allocator,
/// The base fee multiplier used to estimate the gas fees in a transaction
base_fee_multiplier: f64,
/// The chain id of the attached network
chain_id: usize,
/// Channel used to communicate between threads.
/// All events are set in this channel in a FIFO data structure. This is thread safe.
channel: *Channel(EthereumEvents),
/// Callback function for when the connection is closed.
onClose: ?*const fn () void = null,
/// Callback function that will run once a socket event is parsed
onEvent: ?*const fn (args: EthereumEvents) anyerror!void,
/// Callback function that will run once a error is parsed.
onError: ?*const fn (args: []const u8) anyerror!void,
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
retries: u8,
/// The uri of the connection
uri: std.Uri,
/// The underlaying websocket client
ws_client: *ws.Client,

/// Internal RPC event parser.
fn parseRPCEvent(self: *WebSocketHandler, comptime T: type, request: []const u8) !T {
    const parsed = std.json.parseFromSliceLeaky(T, self.allocator, request, .{ .allocate = .alloc_always }) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.allocator, request, .{ .ignore_unknown_fields = true })) |result| {
            wslog.debug("Rpc replied with error message: {s}", .{result.@"error".message});

            if (result.@"error".data) |data|
                wslog.debug("RPC error response data: {s}", .{data});

            // Converts the rpc error codes to zig errors
            return switch (result.@"error".code) {
                .TooManyRequests => error.TooManyRequests,
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

    return parsed;
}
/// This will get run everytime a socket message is found.
/// All messages are parsed and put into the handlers channel.
/// All callbacks will only affect this function.
pub fn handle(self: *WebSocketHandler, message: ws.Message) !void {
    errdefer |err| {
        wslog.debug("Handler errored out: {s}", .{@errorName(err)});
    }

    wslog.debug("Got message: {s}", .{message.data});
    switch (message.type) {
        .text => {
            const parsed = self.parseRPCEvent(EthereumEvents, message.data) catch |err| switch (err) {
                error.TooManyRequests => {
                    // We put the message on the channel. So that if we wanted we could try to parse it
                    // Some nodes may provide the wait period. Needs to be confirmed.
                    self.channel.put(.{ .too_many_requests = .{ .message = message.data } });
                    return;
                },
                else => {
                    if (self.onError) |onError| {
                        try onError(message.data);
                    }

                    wslog.debug("Closing the connection", .{});
                    self.ws_client.closeWithCode(1002);
                    return;
                },
            };

            if (self.onEvent) |onEvent| {
                try onEvent(parsed);
            }

            self.channel.put(parsed);
        },
        else => {},
    }
}

/// Populates the WebSocketHandler pointer.
/// Starts the connection in a seperate process.
pub fn init(self: *WebSocketHandler, opts: InitOptions) !void {
    const arena = try opts.allocator.create(ArenaAllocator);
    errdefer opts.allocator.destroy(arena);

    const channel = try opts.allocator.create(Channel(EthereumEvents));
    errdefer opts.allocator.destroy(channel);

    const ws_client = try opts.allocator.create(ws.Client);
    errdefer opts.allocator.destroy(ws_client);

    const chain: Chains = opts.chain_id orelse .ethereum;

    self.* = .{
        ._arena = arena,
        .allocator = undefined,
        .base_fee_multiplier = opts.base_fee_multiplier,
        .chain_id = @intFromEnum(chain),
        .channel = channel,
        .onClose = opts.onClose,
        .onError = opts.onError,
        .onEvent = opts.onEvent,
        .pooling_interval = opts.pooling_interval,
        .retries = opts.retries,
        .uri = opts.uri,
        .ws_client = ws_client,
    };

    self._arena.* = ArenaAllocator.init(opts.allocator);
    self.allocator = self._arena.allocator();

    self.channel.* = Channel(EthereumEvents).init(self.allocator);
    errdefer self._arena.deinit();

    self.ws_client.* = try self.connect();

    const thread = try std.Thread.spawn(.{}, readLoopOwned, .{self});
    thread.detach();
}

pub fn deinit(self: *WebSocketHandler) void {
    while (@atomicRmw(bool, &self.ws_client._closed, .Xchg, true, .SeqCst)) {
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    const allocator = self._arena.child_allocator;
    self.ws_client.deinit();
    self._arena.deinit();

    allocator.destroy(self.channel);
    allocator.destroy(self._arena);
    if (@atomicLoad(bool, &self.ws_client._closed, .Acquire)) {
        allocator.destroy(self.ws_client);
    }
}
/// Connects to a socket client. This is a blocking operation.
pub fn connect(self: *WebSocketHandler) !ws.Client {
    const scheme = std.http.Client.protocol_map.get(self.uri.scheme) orelse return error.UnsupportedSchema;
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
                const sleep_timing: u64 = @min(10_000, self.pooling_interval * retries);
                std.time.sleep(sleep_timing * std.time.ns_per_ms);
            },
        }

        const b_provider = try ws.bufferProvider(self.allocator, 10, std.math.maxInt(u16));

        var client = ws.connect(self.allocator, self.uri.host.?, port, .{ .tls = scheme == .tls, .max_size = std.math.maxInt(u32), .buffer_provider = b_provider }) catch |err| {
            wslog.debug("Connection failed: {s}", .{@errorName(err)});
            continue;
        };

        const headers = try std.fmt.allocPrint(self.allocator, "Host: {s}", .{self.uri.host.?});
        defer self.allocator.free(headers);

        if (self.uri.path.len == 0)
            return error.MissingUrlPath;

        const path = switch (scheme) {
            .tls => try std.fmt.allocPrint(self.allocator, "{s}", .{self.uri}),
            else => self.uri.path,
        };
        defer if (scheme == .tls) self.allocator.free(path);

        client.handshake(self.uri.path, .{ .headers = headers, .timeout_ms = 5_000 }) catch |err| {
            wslog.debug("Handshake failed: {s}", .{@errorName(err)});
            continue;
        };

        break client;
    };

    return client;
}
/// This is a blocking operation.
/// Call this in a seperate thread.
pub fn readLoopOwned(self: *WebSocketHandler) !void {
    errdefer self.deinit();
    std.os.maybeIgnoreSigpipe();

    self.ws_client.readLoop(self) catch |err| {
        wslog.debug("Read loop reported error: {s}", .{@errorName(err)});
        return;
    };
}
/// Write messages to the websocket connections.
pub fn write(self: *WebSocketHandler, data: []const u8) !void {
    return try self.ws_client.write(@constCast(data));
}
/// Get the first event of the channel.
/// Only call this if you are sure that the channel has messages.
/// Otherwise this will run in a infinite loop.
pub fn getCurrentEvent(self: *WebSocketHandler) !EthereumEvents {
    return self.channel.get();
}
/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
/// Uses the `baseFeePerGas` included in the block to calculate the gas fees.
/// Will return an error in case the `baseFeePerGas` is null.
pub fn estimateFeesPerGas(self: *WebSocketHandler, call_object: EthCall, know_block: ?Block) !EstimateFeeReturn {
    const current_block = know_block orelse try self.getBlockByNumber(.{});

    switch (current_block) {
        inline else => |block_info| {
            switch (call_object) {
                .london => |tx| {
                    const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;
                    const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(current_block);
                    const max_fee = if (tx.maxFeePerGas) |max| max else base_fee + max_priority;

                    return .{ .london = .{ .max_fee_gas = max_fee, .max_priority_fee = max_priority } };
                },
                .legacy => |tx| {
                    const gas_price = if (tx.gasPrice) |price| price else try self.getGasPrice() * std.math.pow(u64, 10, 9);
                    const price = @divExact(gas_price * @as(u64, @intFromFloat(std.math.ceil(self.base_fee_multiplier * std.math.pow(f64, 10, 1)))), std.math.pow(u64, 10, 1));
                    return .{ .legacy = .{ .gas_price = price } };
                },
                else => return error.NotImplementedYet,
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
pub fn estimateGas(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) !Gwei {
    const req_body = try self.prepEthCallRequest(call_object, opts, .eth_estimateGas);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(req_body);
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *WebSocketHandler, know_block: ?Block) !Gwei {
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
pub fn estimateMaxFeePerGas(self: *WebSocketHandler) !Gwei {
    const req_body = try self.prepEmptyArgsRequest(.eth_maxPriorityFeePerGas);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns a list of addresses owned by client.
///
/// RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)
pub fn getAccounts(self: *WebSocketHandler) ![]const Hex {
    const req_body = try self.prepEmptyArgsRequest(.eth_accounts);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .accounts_event => |accounts_event| return accounts_event.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the balance of the account of given address.
///
/// RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)
pub fn getAddressBalance(self: *WebSocketHandler, opts: BalanceRequest) !Wei {
    const req_body = try self.prepAddressRequest(opts, .eth_getBalance);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u256, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions sent from an address.
///
/// RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)
pub fn getAddressTransactionCount(self: *WebSocketHandler, opts: BalanceRequest) !u64 {
    const req_body = try self.prepAddressRequest(opts, .eth_getTransactionCount);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of most recent block.
///
/// RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)
pub fn getBlockByHash(self: *WebSocketHandler, opts: BlockHashRequest) !Block {
    if (!utils.isHash(opts.block_hash)) return error.InvalidHash;
    const include = opts.include_transaction_objects orelse false;

    const Params = std.meta.Tuple(&[_]type{ Hex, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .block_event => |block_event| {
                const block_info = block_event.result orelse return error.InvalidBlockRequest;
                return block_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockByNumber(self: *WebSocketHandler, opts: BlockRequest) !Block {
    const tag: block.BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const Params = std.meta.Tuple(&[_]type{ Hex, bool });
    const params: Params = .{ block_number, include };
    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByNumber, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .block_event => |block_event| {
                const block_info = block_event.result orelse return error.InvalidBlockRequest;
                return block_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockNumber(self: *WebSocketHandler) !u64 {
    const req_body = try self.prepEmptyArgsRequest(.eth_blockNumber);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block hash.
///
/// RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)
pub fn getBlockTransactionCountByHash(self: *WebSocketHandler, block_hash: Hex) !u64 {
    const req_body = try self.prepBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of transactions in a block from a block matching the given block number.
///
/// RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)
pub fn getBlockTransactionCountByNumber(self: *WebSocketHandler, opts: BlockNumberRequest) !u64 {
    const req_body = try self.prepBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the chain ID used for signing replay-protected transactions.
///
/// RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)
pub fn getChainId(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_chainId);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| {
                const chain_id = try std.fmt.parseInt(u64, hex.result, 0);

                if (chain_id != self.chain_id)
                    return error.InvalidChainId;

                return chain_id;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns code at a given address.
///
/// RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)
pub fn getContractCode(self: *WebSocketHandler, opts: BalanceRequest) !Hex {
    const req_body = try self.prepAddressRequest(opts, .eth_getCode);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Polling method for a filter, which returns an array of logs which occurred since last poll or
/// Returns an array of all logs matching filter with given id depending on the selected method
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
/// https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs
pub fn getFilterOrLogChanges(self: *WebSocketHandler, filter_id: usize, method: Extract(EthereumRpcMethods, "eth_getFilterChanges,eth_getFilterLogs")) !Logs {
    const filter = try std.fmt.allocPrint(self.allocator, "0x{x}", .{filter_id});
    defer self.allocator.free(filter);

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{filter}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .logs_event => |logs_event| {
                const logs_info = logs_event.result orelse return error.InvalidFilterId;
                return logs_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns an estimate of the current price per gas in wei.
/// For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.
///
/// RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)
pub fn getGasPrice(self: *WebSocketHandler) !u64 {
    const req_body = try self.prepEmptyArgsRequest(.eth_gasPrice);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(u64, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns an array of all logs matching a given filter object.
///
/// RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)
pub fn getLogs(self: *WebSocketHandler, opts: LogRequestParams) !Logs {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (from_block) |from| if (from[0] == '0') self.allocator.free(from);

    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (to_block) |to| if (to[0] == '0') self.allocator.free(to);

    const request: EthereumRequest([]const LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_getLogs, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .logs_event => |logs_event| {
                const logs_info = logs_event.result orelse return error.InvalidLogRequest;
                return logs_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a transaction by block hash and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)
pub fn getTransactionByBlockHashAndIndex(self: *WebSocketHandler, block_hash: Hex, index: usize) !Transaction {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{ block_hash, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .transaction_event => |tx_event| {
                const transaction_info = tx_event.result orelse return error.TransactionNotFound;
                return transaction_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a transaction by block number and transaction index position.
///
/// RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)
pub fn getTransactionByBlockNumberAndIndex(self: *WebSocketHandler, opts: BlockNumberRequest, index: usize) !Transaction {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{ block_number, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockNumberAndIndex, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .transaction_event => |tx_event| {
                const transaction_info = tx_event.result orelse return error.TransactionNotFound;
                return transaction_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the information about a transaction requested by transaction hash.
///
/// RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)
pub fn getTransactionByHash(self: *WebSocketHandler, transaction_hash: Hex) !Transaction {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionByHash, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .transaction_event => |tx_event| {
                const transaction_info = tx_event.result orelse return error.TransactionNotFound;
                return transaction_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the receipt of a transaction by transaction hash.
///
/// RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)
pub fn getTransactionReceipt(self: *WebSocketHandler, transaction_hash: Hex) !TransactionReceipt {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionReceipt, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .receipt_event => |receipt_event| {
                const transaction_info = receipt_event.result orelse return error.TransactionReceiptNotFound;
                return transaction_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a uncle of a block by hash and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)
pub fn getUncleByBlockHashAndIndex(self: *WebSocketHandler, block_hash: Hex, index: usize) !Block {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ Hex, Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockHashAndIndex, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .block_event => |block_event| {
                const block_info = block_event.result orelse return error.InvalidBlockHashOrIndex;
                return block_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns information about a uncle of a block by number and uncle index position.
///
/// RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)
pub fn getUncleByBlockNumberAndIndex(self: *WebSocketHandler, opts: BlockNumberRequest, index: usize) !Block {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .block_event => |block_event| {
                const block_info = block_event.result orelse return error.InvalidBlockNumberOrIndex;
                return block_info;
            },
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a transaction_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Returns the number of uncles in a block from a block matching the given block hash.
///
/// RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)
pub fn getUncleCountByBlockHash(self: *WebSocketHandler, block_hash: Hex) !usize {
    const req_body = try self.prepBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}
/// Returns the number of uncles in a block from a block matching the given block number.
///
/// RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)
pub fn getUncleCountByBlockNumber(self: *WebSocketHandler, opts: BlockNumberRequest) !usize {
    const req_body = try self.prepBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(usize, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates a filter in the node, to notify when a new block arrives.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)
pub fn newBlockFilter(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_newBlockFilter);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(usize, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates a filter object, based on filter options, to notify when the state changes (logs).
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)
pub fn newLogFilter(self: *WebSocketHandler, opts: LogFilterRequestParams) !usize {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (from_block) |from| if (from[0] == '0') self.allocator.free(from);

    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (to_block) |to| if (to[0] == '0') self.allocator.free(to);

    const request: types.EthereumRequest([]const log.LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_newFilter, .id = 1 };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(usize, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates a filter in the node, to notify when new pending transactions arrive.
/// To check if the state has changed, call `getFilterOrLogChanges`.
///
/// RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)
pub fn newPendingTransactionFilter(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_newPendingTransactionFilter);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return try std.fmt.parseInt(usize, hex.result, 0),
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Executes a new message call immediately without creating a transaction on the block chain.
/// Often used for executing read-only smart contract functions,
/// for example the balanceOf for an ERC-20 contract.
///
/// Call object must be prefilled before hand. Including the data field.
/// This will just make the request to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn sendEthCall(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest) !Hex {
    const req_body = try self.prepEthCallRequest(call_object, opts, .eth_call);
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates new message call transaction or a contract creation for signed transactions.
/// Transaction must be serialized and signed before hand.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn sendRawTransaction(self: *WebSocketHandler, serialized_hex_tx: Hex) !Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{serialized_hex_tx}, .method = .eth_sendRawTransaction, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Uninstalls a filter with given id. Should always be called when watch is no longer needed.
/// Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.
///
/// RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)
pub fn uninstalllFilter(self: *WebSocketHandler, id: usize) !bool {
    const filter_id = try std.fmt.allocPrint(self.allocator, "0x{x}", .{id});
    defer self.allocator.free(filter_id);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{filter_id}, .method = .eth_uninstallFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .bool_event => |bool_event| return bool_event.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Unsubscribe from different Ethereum event types with a regular RPC call
/// with eth_unsubscribe as the method and the subscriptionId as the first parameter.
///
/// RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)
pub fn unsubscribe(self: *WebSocketHandler, sub_id: Hex) !bool {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{sub_id}, .method = .eth_unsubscribe, .id = self.allocator };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .bool_event => |bool_event| return bool_event.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Emits new blocks that are added to the blockchain.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
pub fn watchNewBlocks(self: *WebSocketHandler) !Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{"newHeads"}, .method = .eth_subscribe, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Emits logs attached to a new block that match certain topic filters.
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)
pub fn watchLogs(self: *WebSocketHandler, opts: LogFilterRequestParams) !Hex {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (from_block) |from| if (from[0] == '0') self.allocator.free(from);

    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (to_block) |to| if (to[0] == '0') self.allocator.free(to);
    const request: EthereumRequest(std.meta.Tuple(&[_]type{ []const u8, log.LogRequest })) = .{ .params = &.{ "logs", .{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics } }, .method = .eth_subscribe, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Emits transaction hashes that are sent to the network and marked as "pending".
///
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)
pub fn watchTransactions(self: *WebSocketHandler) !Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{"newPendingTransactions"}, .method = .eth_subscribe, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(req_body));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
}
/// Creates a new subscription for desired events. Sends data as soon as it occurs
///
/// This expects the request to already be prepared beforehand.
/// Since we have no way of knowing all possible or custom RPC methods that nodes can provide.
/// RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)
pub fn watchWebsocketEvent(self: *WebSocketHandler, request: []const u8) !Hex {
    var retries: u8 = 0;
    while (true) : (retries += 1) {
        if (retries > self.retries)
            return error.ReachedMaxRetryLimit;

        try self.write(@constCast(request));
        switch (self.channel.get()) {
            .hex_event => |hex| return hex.result,
            .too_many_requests => {
                // Exponential backoff
                const backoff: u32 = std.math.shl(u8, 1, retries) * 200;
                wslog.debug("Error 429 found. Retrying in {d} ms", .{backoff});

                std.time.sleep(std.time.ns_per_ms * backoff);
                continue;
            },
            else => |eve| {
                wslog.debug("Found incorrect event named: {s}. Expected a hex_event.", .{@tagName(eve)});
                return error.InvalidEventFound;
            },
        }
    }
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
pub fn waitForTransactionReceipt(self: *WebSocketHandler, tx_hash: Hex, confirmations: u8) !?TransactionReceipt {
    var tx: ?Transaction = null;
    var block_number = try self.getBlockNumber();
    var receipt: ?TransactionReceipt = self.getTransactionReceipt(tx_hash) catch |err| switch (err) {
        error.TransactionReceiptNotFound => null,
        else => return err,
    };

    // The receipt can be null here
    if (confirmations == 0)
        return receipt;

    const sub_id = try self.watchNewBlocks();

    var retries: u8 = 0;
    var valid_confirmations: u8 = 0;
    while (true) : (retries += 1) {
        if (retries - valid_confirmations > self.retries)
            return error.FailedToGetReceipt;

        const event = self.channel.get();

        switch (event) {
            .new_heads_event => {},
            else => {
                // Decrements the retries since we didn't get a block subscription
                retries -= 1;
                continue;
            },
        }

        if (receipt) |tx_receipt| {
            const number: ?u64 = switch (tx_receipt) {
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
                error.TransactionNotFound => continue,
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

                        wslog.debug("Transaction was replace by a newer one", .{});

                        switch (replaced_tx) {
                            inline else => |replacement| switch (tx.?) {
                                inline else => |original| {
                                    if (std.mem.eql(u8, replacement.from, original.from) and replacement.value == original.value)
                                        wslog.debug("Original transaction was repriced", .{});

                                    if (replacement.to) |replaced_to| {
                                        if (std.mem.eql(u8, replacement.from, replaced_to) and replacement.value == 0)
                                            wslog.debug("Original transaction was canceled", .{});
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
                },
                else => return err,
            };

            const valid_receipt = receipt.?;
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
    }
    const success = try self.unsubscribe(sub_id);

    if (!success)
        return error.FailedToUnsubscribe;

    return receipt;
}
/// Runs the callback once the handler close method gets called by the ws_client
pub fn close(self: *WebSocketHandler) void {
    if (self.onClose) |onClose| {
        return onClose();
    }
}

fn prepEmptyArgsRequest(self: *WebSocketHandler, method: EthereumRpcMethods) ![]const u8 {
    const Params = std.meta.Tuple(&[_]type{});
    const request: EthereumRequest(Params) = .{ .params = .{}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepBlockNumberRequest(self: *WebSocketHandler, opts: BlockNumberRequest, method: EthereumRpcMethods) ![]const u8 {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{block_number}, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepBlockHashRequest(self: *WebSocketHandler, block_hash: []const u8, method: EthereumRpcMethods) ![]const u8 {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{block_hash}, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepAddressRequest(self: *WebSocketHandler, opts: BalanceRequest, method: EthereumRpcMethods) ![]const u8 {
    if (!try utils.isAddress(self.allocator, opts.address)) return error.InvalidAddress;

    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const request: types.EthereumRequest(HexRequestParameters) = .{ .params = &.{ opts.address, block_number }, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepEthCallRequest(self: *WebSocketHandler, call_object: EthCall, opts: BlockNumberRequest, method: EthereumRpcMethods) ![]const u8 {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const call = try utils.hexifyEthCall(self.allocator, call_object);

    const Params = std.meta.Tuple(&[_]type{ EthCallHexed, Hex });
    const request: types.EthereumRequest(Params) = .{ .params = .{ call, block_number }, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });

    return req_body;
}

test "GetBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_req = try ws_client.getBlockNumber();

    try testing.expect(block_req != 0);
}

test "GetChainId" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const chain = try ws_client.getChainId();

    try testing.expectEqual(1, chain);
}

test "GetBlock" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockByNumber(.{});
    try testing.expect(block_info == .beacon);
    try testing.expect(block_info.beacon.number != null);

    const block_old = try ws_client.getBlockByNumber(.{ .block_number = 696969 });
    try testing.expect(block_old == .legacy);
}

test "GetBlockByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockByHash(.{ .block_hash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(block_info == .beacon);
    try testing.expect(block_info.beacon.number != null);
}

test "GetBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getBlockTransactionCountByNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockTransactionCountByNumber(.{});
    try testing.expect(block_info != 0);
}

test "getBlockTransactionCountByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getAccounts" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const accounts = try ws_client.getAccounts();
    try testing.expect(accounts.len != 0);
}

test "gasPrice" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gasPrice = try ws_client.getGasPrice();
    try testing.expect(gasPrice != 0);
}

test "getCode" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const code = try ws_client.getContractCode(.{ .address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" });
    try testing.expectEqualStrings(code, "0x6060604052600436106100af576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306fdde03146100b9578063095ea7b31461014757806318160ddd146101a157806323b872dd146101ca5780632e1a7d4d14610243578063313ce5671461026657806370a082311461029557806395d89b41146102e2578063a9059cbb14610370578063d0e30db0146103ca578063dd62ed3e146103d4575b6100b7610440565b005b34156100c457600080fd5b6100cc6104dd565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561010c5780820151818401526020810190506100f1565b50505050905090810190601f1680156101395780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561015257600080fd5b610187600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061057b565b604051808215151515815260200191505060405180910390f35b34156101ac57600080fd5b6101b461066d565b6040518082815260200191505060405180910390f35b34156101d557600080fd5b610229600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061068c565b604051808215151515815260200191505060405180910390f35b341561024e57600080fd5b61026460048080359060200190919050506109d9565b005b341561027157600080fd5b610279610b05565b604051808260ff1660ff16815260200191505060405180910390f35b34156102a057600080fd5b6102cc600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610b18565b6040518082815260200191505060405180910390f35b34156102ed57600080fd5b6102f5610b30565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561033557808201518184015260208101905061031a565b50505050905090810190601f1680156103625780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561037b57600080fd5b6103b0600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091908035906020019091905050610bce565b604051808215151515815260200191505060405180910390f35b6103d2610440565b005b34156103df57600080fd5b61042a600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610be3565b6040518082815260200191505060405180910390f35b34600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055503373ffffffffffffffffffffffffffffffffffffffff167fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c346040518082815260200191505060405180910390a2565b60008054600181600116156101000203166002900480601f0160208091040260200160405190810160405280929190818152602001828054600181600116156101000203166002900480156105735780601f1061054857610100808354040283529160200191610573565b820191906000526020600020905b81548152906001019060200180831161055657829003601f168201915b505050505081565b600081600460003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b60003073ffffffffffffffffffffffffffffffffffffffff1631905090565b600081600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054101515156106dc57600080fd5b3373ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16141580156107b457507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205414155b156108cf5781600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020541015151561084457600080fd5b81600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055505b81600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000828254039250508190555081600360008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a3600190509392505050565b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410151515610a2757600080fd5b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055503373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501515610ab457600080fd5b3373ffffffffffffffffffffffffffffffffffffffff167f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65826040518082815260200191505060405180910390a250565b600260009054906101000a900460ff1681565b60036020528060005260406000206000915090505481565b60018054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610bc65780601f10610b9b57610100808354040283529160200191610bc6565b820191906000526020600020905b815481529060010190602001808311610ba957829003601f168201915b505050505081565b6000610bdb33848461068c565b905092915050565b60046020528160005260406000206020528060005260406000206000915091505054815600a165627a7a72305820deb4c2ccab3c2fdca32ab3f46728389c2fe2c165d5fafa07661e4e004f6c344a0029");
}

test "getAddressBalance" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const address = try ws_client.getAddressBalance(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(address, try utils.parseEth(10000));
}

test "getUncleCountByBlockHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const uncle = try ws_client.getUncleCountByBlockHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expectEqual(uncle, 0);
}

test "getUncleCountByBlockNumber" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const uncle = try ws_client.getUncleCountByBlockNumber(.{});
    try testing.expectEqual(uncle, 0);
}

test "getLogs" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const logs = try ws_client.getLogs(.{ .blockHash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(logs.len != 0);
}

test "getTransactionByBlockNumberAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const tx = try ws_client.getTransactionByBlockNumberAndIndex(.{ .block_number = 16777215 }, 0);
    try testing.expect(tx == .london);
}

test "getTransactionByBlockHashAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const tx = try ws_client.getTransactionByBlockHashAndIndex("0xf34c3c11b35466e5595e077239e6b25a7c3ec07a214b2492d42ba6d73d503a1b", 0);
    try testing.expect(tx == .london);
}

test "getAddressTransactionCount" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const nonce = try ws_client.getAddressTransactionCount(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(nonce, 605);
}

test "getTransactionByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const eip1559 = try ws_client.getTransactionByHash("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(eip1559 == .london);

    // Remove because they fail on CI run.
    // const legacy = try pub_client.getTransactionByHash("0xf9ffe354d26160616844278c4fcbfe0eaa5589da48bc1359eda81fc1ce18b51a");
    // try testing.expect(legacy == .legacy);
    //
    // const tx_untyped = try pub_client.getTransactionByHash("0x0bad3271acf0f10e56caf39187c956583710e1295ee3369a442beda0a666b27a");
    // try testing.expect(tx_untyped == .untyped);
}

test "getTransactionReceipt" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const receipt = try ws_client.getTransactionReceipt("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(receipt.london.status != null);

    // Pre-Byzantium
    const legacy = try ws_client.getTransactionReceipt("0x4dadc87da2b7c47125fb7e4102d95457830e44d2fbcd45537d91f8be1e5f6130");
    try testing.expect(legacy.london.root != null);
}

test "estimateGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateGas(.{ .london = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, .{});
    try testing.expect(gas != 0);
}

test "estimateFeesPerGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateFeesPerGas(.{ .london = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, null);
    try testing.expect(gas.london.max_fee_gas != 0);
    try testing.expect(gas.london.max_priority_fee != 0);
}

test "estimateMaxFeePerGasManual" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateMaxFeePerGasManual(null);
    try testing.expect(gas != 0);
}
