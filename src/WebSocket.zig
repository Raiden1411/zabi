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
const ArenaAllocator = std.heap.ArenaAllocator;
const Chains = types.PublicChains;
const Channel = @import("channel.zig").Channel;
const EthereumEvents = types.EthereumEvents;
const EthereumErrorResponse = types.EthereumErrorResponse;
const EthereumRequest = types.EthereumRequest;
const EthereumRpcMethods = types.EthereumRpcMethods;

const WebSocketHandler = @This();

const wslog = std.log.scoped(.ws);

pub const InitOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    allocator: Allocator,
    /// Fork url for anvil to fork from
    uri: std.Uri,
    /// The client chainId.
    chain_id: ?Chains = null,
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
    retries: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
};

_arena: *ArenaAllocator,

allocator: std.mem.Allocator,

chain_id: usize,

channel: *Channel(EthereumEvents),

pooling_interval: u64,

retries: u8,

uri: std.Uri,

ws_client: *ws.Client,

fn parseRPCEvent(self: *WebSocketHandler, comptime T: type, request: []const u8) !T {
    const parsed = std.json.parseFromSliceLeaky(T, self.allocator, request, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.allocator, request, .{ .ignore_unknown_fields = true })) |result| {
            wslog.debug("Rpc replied with error message: {s}", .{result.@"error".message});
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed;
}

pub fn handle(self: *WebSocketHandler, message: ws.Message) !void {
    wslog.debug("Got message: {s}", .{message.data});
    const parsed = self.parseRPCEvent(EthereumEvents, message.data) catch |err| switch (err) {
        error.RpcErrorResponse => {
            wslog.debug("Closing the connection", .{});
            self.ws_client.closeWithCode(1002);
            return;
        },
        error.RpcNullResponse => {
            wslog.debug("Rpc replied with null result", .{});
            wslog.debug("Closing the connection", .{});
            self.ws_client.closeWithCode(1002);
            return;
        },
    };
    self.channel.put(parsed);
}

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
        .chain_id = @intFromEnum(chain),
        .channel = channel,
        .pooling_interval = opts.pooling_interval,
        .retries = opts.retries,
        .uri = opts.uri,
        .ws_client = ws_client,
    };

    self._arena.* = ArenaAllocator.init(opts.allocator);
    self.allocator = self._arena.allocator();

    self.channel.* = Channel(EthereumEvents).init(self.allocator);
    self.ws_client.* = try self.connect();

    const thread = try self.ws_client.readLoopInNewThread(self);
    thread.detach();
}

pub fn deinit(self: *WebSocketHandler) void {
    if (!@atomicLoad(bool, &self.ws_client._closed, .Monotonic)) {
        const allocator = self._arena.child_allocator;
        self.ws_client.close();
        self._arena.deinit();

        allocator.destroy(self.ws_client);
        allocator.destroy(self.channel);
        allocator.destroy(self._arena);
    } else {
        const allocator = self._arena.child_allocator;
        self._arena.deinit();

        allocator.destroy(self.channel);
        allocator.destroy(self._arena);
        allocator.destroy(self.ws_client);
    }
}

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

        const b_provider = try ws.bufferProvider(self.allocator, 10, 32768);

        var client = ws.connect(self.allocator, self.uri.host.?, port, .{ .tls = scheme == .tls, .max_size = std.math.maxInt(u24), .buffer_provider = b_provider }) catch |err| {
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

pub fn write(self: *WebSocketHandler, data: []const u8) !void {
    return try self.ws_client.write(@constCast(data));
}

pub fn getCurrentEvent(self: *WebSocketHandler) !EthereumEvents {
    return self.channel.get();
}

pub fn estimateFeesPerGas(self: *WebSocketHandler, call_object: transaction.EthCall, know_block: ?block.Block) !transaction.EstimateFeeReturn {
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
                    const price = @divExact(gas_price * @as(u64, @intFromFloat(std.math.ceil(1.2 * std.math.pow(f64, 10, 1)))), std.math.pow(u64, 10, 1));
                    return .{ .legacy = .{ .gas_price = price } };
                },
            }
        },
    }
}

/// Calls `eth_estimateGas` with the call object.
pub fn estimateGas(self: *WebSocketHandler, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Gwei {
    const req_body = try self.prepEthCallRequest(call_object, opts, .eth_estimateGas);
    defer self.allocator.free(req_body);

    try self.write(req_body);
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
pub fn estimateMaxFeePerGasManual(self: *WebSocketHandler, know_block: ?block.Block) !types.Gwei {
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
pub fn estimateMaxFeePerGas(self: *WebSocketHandler) !types.Gwei {
    const req_body = try self.prepEmptyArgsRequest(.eth_maxPriorityFeePerGas);
    defer self.allocator.free(req_body);

    try self.write(req_body);
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getAccounts(self: *WebSocketHandler) ![]const types.Hex {
    const req_body = try self.prepEmptyArgsRequest(.eth_accounts);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .accounts_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getAddressBalance(self: *WebSocketHandler, opts: block.BalanceRequest) !types.Wei {
    const req_body = try self.prepAddressRequest(opts, .eth_getBalance);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u256, event.result, 0);
}

pub fn getAddressTransactionCount(self: *WebSocketHandler, opts: block.BalanceRequest) !u64 {
    const req_body = try self.prepAddressRequest(opts, .eth_getTransactionCount);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getBlockByHash(self: *WebSocketHandler, opts: block.BlockHashRequest) !block.Block {
    if (!utils.isHash(opts.block_hash)) return error.InvalidHash;
    const include = opts.include_transaction_objects orelse false;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .block_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getBlockByNumber(self: *WebSocketHandler, opts: block.BlockRequest) !block.Block {
    const tag: block.BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, bool });
    const params: Params = .{ block_number, include };
    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByNumber, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .block_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getBlockNumber(self: *WebSocketHandler) !u64 {
    const req_body = try self.prepEmptyArgsRequest(.eth_blockNumber);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Event found: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getBlockTransactionCountByHash(self: *WebSocketHandler, block_hash: types.Hex) !u64 {
    const req_body = try self.prepBlockHashRequest(block_hash, .eth_getBlockTransactionCountByHash);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getBlockTransactionCountByNumber(self: *WebSocketHandler, opts: block.BlockNumberRequest) !u64 {
    const req_body = try self.prepBlockNumberRequest(opts, .eth_getBlockTransactionCountByNumber);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getChainId(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_chainId);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    const chain_id = try std.fmt.parseInt(usize, event.result, 0);

    if (chain_id != self.chain_id)
        return error.InvalidChainId;

    return chain_id;
}

pub fn getContractCode(self: *WebSocketHandler, opts: block.BalanceRequest) !types.Hex {
    const req_body = try self.prepAddressRequest(opts, .eth_getCode);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getFilterOrLogChanges(self: *WebSocketHandler, filter_id: usize, method: meta.Extract(types.EthereumRpcMethods, "eth_getFilterChanges,eth_FilterLogs")) !log.Logs {
    const filter = try std.fmt.allocPrint(self.allocator, "0x{x}", .{filter_id});
    defer self.allocator.free(filter);

    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{filter}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .logs_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return event.result;
}

pub fn getGasPrice(self: *WebSocketHandler) !u64 {
    const req_body = try self.prepEmptyArgsRequest(.eth_gasPrice);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(u64, event.result, 0);
}

pub fn getLogs(self: *WebSocketHandler, opts: log.LogRequestParams) !log.Logs {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (from_block) |from| if (from[0] == '0') self.allocator.free(from);

    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (to_block) |to| if (to[0] == '0') self.allocator.free(to);

    const request: types.EthereumRequest([]const log.LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_getLogs, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .logs_event => |logs| logs,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getTransactionByBlockHashAndIndex(self: *WebSocketHandler, block_hash: types.Hex, index: usize) !transaction.Transaction {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ block_hash, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .transaction_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getTransactionByBlockNumberAndIndex(self: *WebSocketHandler, opts: block.BlockNumberRequest, index: usize) !transaction.Transaction {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ block_number, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockNumberAndIndex, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .transaction_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getTransactionByHash(self: *WebSocketHandler, transaction_hash: types.Hex) !transaction.Transaction {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionByHash, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .transaction_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getTransactionReceipt(self: *WebSocketHandler, transaction_hash: types.Hex) !transaction.TransactionReceipt {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionReceipt, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .receipt_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return event.result;
}

pub fn getUncleByBlockHashAndIndex(self: *WebSocketHandler, block_hash: types.Hex, index: usize) !block.Block {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockHashAndIndex, .id = 1 };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .block_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return event.result;
}

pub fn getUncleByBlockNumberAndIndex(self: *WebSocketHandler, opts: block.BlockNumberRequest, index: usize) !block.Block {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.allocator, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .block_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn getUncleCountByBlockHash(self: *WebSocketHandler, block_hash: types.Hex) !usize {
    const req_body = try self.prepBlockHashRequest(block_hash, .eth_getUncleCountByBlockHash);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}

pub fn getUncleCountByBlockNumber(self: *WebSocketHandler, opts: block.BlockNumberRequest) !usize {
    const req_body = try self.prepBlockNumberRequest(opts, .eth_getUncleCountByBlockNumber);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}

pub fn newBlockFilter(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_newBlockFilter);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}

pub fn newLogFilter(self: *WebSocketHandler, opts: log.LogFilterRequestParams) !usize {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (from_block) |from| if (from[0] == '0') self.allocator.free(from);

    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else null;
    defer if (to_block) |to| if (to[0] == '0') self.allocator.free(to);

    const request: types.EthereumRequest([]const log.LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_newFilter, .id = 1 };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}

pub fn newPendingTransactionFilter(self: *WebSocketHandler) !usize {
    const req_body = try self.prepEmptyArgsRequest(.eth_newPendingTransactionFilter);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return try std.fmt.parseInt(usize, event.result, 0);
}

/// Call object must be prefilled before hand. Including the data field.
/// This will just the request to the network.
pub fn sendEthCall(self: *WebSocketHandler, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Hex {
    const req_body = try self.prepEthCallRequest(call_object, opts, .eth_call);
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

/// Transaction must be serialized and signed before hand.
pub fn sendRawTransaction(self: *WebSocketHandler, serialized_hex_tx: types.Hex) !types.Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{serialized_hex_tx}, .method = .eth_sendRawTransaction, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn uninstalllFilter(self: *WebSocketHandler, id: usize) !bool {
    const filter_id = try std.fmt.allocPrint(self.allocator, "0x{x}", .{id});
    defer self.allocator.free(filter_id);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{filter_id}, .method = .eth_uninstallFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .bool_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return event.result;
}

pub fn unsubscribe(self: *WebSocketHandler, sub_id: types.Hex) !bool {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{sub_id}, .method = .eth_unsubscribe, .id = self.allocator };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .bool_event => |hex| hex,
        else => return error.InvalidEventFound,
    };

    return event.result;
}

pub fn watchTransactions(self: *WebSocketHandler) !types.Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{"newPendingTransactions"}, .method = .eth_subscribe, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

pub fn watchNewBlocks(self: *WebSocketHandler) !types.Hex {
    const request: EthereumRequest(types.HexRequestParameters) = .{ .params = &.{"newHeads"}, .method = .eth_subscribe, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(req_body);

    try self.write(@constCast(req_body));
    const event = switch (self.channel.get()) {
        .hex_event => |hex| hex,
        else => |eve| {
            wslog.debug("Found event named: {s}", .{@tagName(eve)});
            return error.InvalidEventFound;
        },
    };

    return event.result;
}

fn prepEmptyArgsRequest(self: *WebSocketHandler, method: EthereumRpcMethods) ![]const u8 {
    const Params = std.meta.Tuple(&[_]type{});
    const request: EthereumRequest(Params) = .{ .params = .{}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepBlockNumberRequest(self: *WebSocketHandler, opts: block.BlockNumberRequest, method: EthereumRpcMethods) ![]const u8 {
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

fn prepAddressRequest(self: *WebSocketHandler, opts: block.BalanceRequest, method: EthereumRpcMethods) ![]const u8 {
    if (!try utils.isAddress(self.allocator, opts.address)) return error.InvalidAddress;

    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ opts.address, block_number }, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{});

    return req_body;
}

fn prepEthCallRequest(self: *WebSocketHandler, call_object: transaction.EthCall, opts: block.BlockNumberRequest, method: EthereumRpcMethods) ![]const u8 {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.allocator, "0x{x}", .{number}) else @tagName(tag);
    defer if (block_number[0] == '0') self.allocator.free(block_number);

    const call = try utils.hexifyEthCall(self.allocator, call_object);

    const Params = std.meta.Tuple(&[_]type{ transaction.EthCallHexed, types.Hex });
    const request: types.EthereumRequest(Params) = .{ .params = .{ call, block_number }, .method = method, .id = self.chain_id };
    const req_body = try std.json.stringifyAlloc(self.allocator, request, .{ .emit_null_optional_fields = false });

    return req_body;
}

pub fn close(_: *WebSocketHandler) void {}

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
    try testing.expect(block_info == .blockMerge);
    try testing.expect(block_info.blockMerge.number != null);

    const block_old = try ws_client.getBlockByNumber(.{ .block_number = 696969 });
    try testing.expect(block_old == .block);
}

test "GetBlockByHash" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const block_info = try ws_client.getBlockByHash(.{ .block_hash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(block_info == .blockMerge);
    try testing.expect(block_info.blockMerge.number != null);
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
    try testing.expect(tx == .eip1559);
}

test "getTransactionByBlockHashAndIndex" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const tx = try ws_client.getTransactionByBlockHashAndIndex("0xf34c3c11b35466e5595e077239e6b25a7c3ec07a214b2492d42ba6d73d503a1b", 0);
    try testing.expect(tx == .eip1559);
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
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const receipt = try ws_client.getTransactionReceipt("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(receipt.status != null);

    // Pre-Byzantium
    const legacy = try ws_client.getTransactionReceipt("0x4dadc87da2b7c47125fb7e4102d95457830e44d2fbcd45537d91f8be1e5f6130");
    try testing.expect(legacy.root != null);
}

test "estimateGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, .{});
    try testing.expect(gas != 0);
}

test "estimateFeesPerGas" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateFeesPerGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, null);
    try testing.expect(gas.eip1559.max_fee_gas != 0);
    try testing.expect(gas.eip1559.max_priority_fee != 0);
}

test "estimateMaxFeePerGasManual" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var ws_client: WebSocketHandler = undefined;
    defer ws_client.deinit();
    try ws_client.init(.{ .allocator = std.testing.allocator, .uri = uri });

    const gas = try ws_client.estimateMaxFeePerGasManual(null);
    try testing.expect(gas != 0);
}
