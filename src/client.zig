const block = @import("block.zig");
const http = std.http;
const meta = @import("meta/meta.zig");
const std = @import("std");
const transaction = @import("transaction.zig");
const types = @import("meta/types.zig");
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Uri = std.Uri;

pub fn EthereumRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: EthereumRpcMethods,
        params: T,
        id: usize = 1,
    };
}

pub fn EthereumResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8,
        id: usize,
        result: T,

        pub usingnamespace if (@typeInfo(T) == .Int) meta.RequestParser(@This()) else struct {};
    };
}

pub const ErrorResponse = struct {
    code: isize,
    message: []const u8,
};

pub const EthereumErrorResponse = struct { jsonrpc: []const u8, id: usize, @"error": ErrorResponse };

/// Set of public rpc actions.
pub const EthereumRpcMethods = enum {
    eth_chainId,
    eth_gasPrice,
    eth_accounts,
    eth_getBalance,
    eth_getBlockByNumber,
    eth_getBlockByHash,
    eth_blockNumber,
    eth_getTransactionCount,
    eth_getBlockTransactionCountByHash,
    eth_getBlockTransactionCountByNumber,
    eth_getUncleCountByBlockHash,
    eth_getUncleCountByBlockNumber,
    eth_getCode,
    eth_getTransactionByHash,
    eth_getTransactionByBlockHashAndIndex,
    eth_getTransactionByBlockNumberAndIndex,
    eth_getTransactionReceit,
    eth_getUncleByBlockHashAndIndex,
    eth_getUncleByBlockNumberAndIndex,
    eth_newFilter,
    eth_newBlockFilter,
    eth_newPendingTransactionFilter,
    eth_uninstallFilter,
    eth_getFilterChanges,
    eth_getFilterLogs,
    eth_getLogs,
    eth_sign,
    eth_signTransaction,
    eth_sendTransaction,
    eth_sendRawTransaction,
    eth_call,
    eth_estimateGas,
};

/// This allocator will get set by the arena.
alloc: Allocator,
/// The arena where all allocations will leave.
arena: *ArenaAllocator,
/// The set of predifined headers use for the rpc calls.
headers: *http.Headers,
/// The underlaying http client used to manage all the calls.
client: *http.Client,
/// The uri of the provided init string.
uri: Uri,

const PubClient = @This();

pub fn init(alloc: Allocator, url: []const u8) !PubClient {
    var pub_client: PubClient = .{ .alloc = undefined, .arena = try alloc.create(ArenaAllocator), .client = try alloc.create(http.Client), .headers = try alloc.create(http.Headers), .uri = try Uri.parse(url) };
    errdefer {
        alloc.destroy(pub_client.arena);
        alloc.destroy(pub_client.client);
        alloc.destroy(pub_client.headers);
    }

    pub_client.arena.* = ArenaAllocator.init(std.testing.allocator);
    pub_client.alloc = pub_client.arena.allocator();
    errdefer pub_client.arena.deinit();

    pub_client.headers.* = try http.Headers.initList(pub_client.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    pub_client.client.* = http.Client{ .allocator = pub_client.alloc };

    return pub_client;
}

pub fn deinit(self: @This()) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
    allocator.destroy(self.headers);
    allocator.destroy(self.client);
}

pub fn getChainId(self: PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_chainId);
}

pub fn getGasPrice(self: PubClient) !types.Gwei {
    return self.fetchWithEmptyArgs(u64, .eth_gasPrice);
}

pub fn getAccounts(self: PubClient) ![]const types.Hex {
    return self.fetchWithEmptyArgs([]const types.Hex, .eth_accounts);
}

pub fn getBlockNumber(self: PubClient) !u64 {
    return self.fetchWithEmptyArgs(u64, .eth_blockNumber);
}

pub fn newBlockFilter(self: PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_newBlockFilter);
}

pub fn newPendingTransactionFilter(self: PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_newPendingTransactionFilter);
}

pub fn getBlockTransactionCountByHash(self: PubClient, block_hash: types.Hex) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getBlockTransactionCountByHash);
}

pub fn getBlockTransactionCountByNumber(self: PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getBlockTransactionCountByNumber);
}

pub fn getUncleCountByBlockHash(self: PubClient, block_hash: types.Hex) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getUncleCountByBlockHash);
}

pub fn getUncleCountByBlockNumber(self: PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getUncleCountByBlockNumber);
}

pub fn getAddressBalance(self: PubClient, opts: block.BalanceRequest) !types.Wei {
    return self.fetchByAddress(types.Wei, opts, .eth_getBalance);
}

pub fn getAddressTransactionCount(self: PubClient, opts: block.BalanceRequest) !usize {
    return self.fetchByAddress(usize, opts, .eth_getTransactionCount);
}

pub fn getContractCode(self: PubClient, opts: block.BalanceRequest) !types.Hex {
    return self.fetchByAddress(types.Hex, opts, .eth_getCode);
}

pub fn getBlockByNumber(self: PubClient, opts: block.BlockRequest) !block.Block {
    const tag: block.BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ []const u8, bool });
    const params: Params = .{ block_number, include };
    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByNumber };

    return self.fetchBlock(request);
}

pub fn getBlockByHash(self: PubClient, opts: block.BlockHashRequest) !block.Block {
    if (!utils.isHash(opts.block_hash)) return error.InvalidHash;
    const include = opts.include_transaction_objects orelse false;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash };

    return self.fetchBlock(request);
}

pub fn getUncleByBlockHashAndIndex(self: PubClient, block_hash: types.Hex, index: usize) !block.Block {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockHashAndIndex };

    return self.fetchBlock(request);
}

pub fn getUncleByBlockNumberAndIndex(self: PubClient, opts: block.BlockNumberRequest, index: usize) !block.Block {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex };

    return self.fetchBlock(request);
}

pub fn getTransactionByHash(self: PubClient, transaction_hash: types.Hex) !transaction.Transaction {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{types.Hex});
    const params: Params = .{transaction_hash};

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByHash };
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(transaction.Transaction), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

pub fn getTransactionByBlockHashAndIndex(self: PubClient, block_hash: types.Hex, index: usize) !transaction.Transaction {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex };
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(transaction.Transaction), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

pub fn getTransactionByBlockNumberAndIndex(self: PubClient, opts: block.BlockNumberRequest, index: usize) !transaction.Transaction {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex };
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(transaction.Transaction), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

pub fn uninstalllFilter(self: PubClient, id: usize) !bool {
    const filter_id = try std.fmt.allocPrint(self.alloc, "0x{x}", .{id});

    const Params = std.meta.Tuple(&[_]type{types.Hex});
    const params: Params = .{filter_id};

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_uninstallFilter };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(bool), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchByBlockNumber(self: PubClient, opts: block.BlockNumberRequest, method: EthereumRpcMethods) !usize {
    const tag: block.BalanceRequest = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{types.Hex});
    const params: Params = .{block_number};

    const request: EthereumRequest(Params) = .{ .params = params, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(usize), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchByBlockHash(self: PubClient, block_hash: []const u8, method: EthereumRpcMethods) !usize {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{types.Hex});
    const params: Params = .{block_hash};

    const request: EthereumRequest(Params) = .{ .params = params, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(usize), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchByAddress(self: PubClient, comptime T: type, opts: block.BalanceRequest, method: EthereumRpcMethods) !T {
    if (!try utils.isAddress(self.alloc, opts.address)) return error.InvalidAddress;
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const request: EthereumRequest(Params) = .{ .params = .{ opts.address, block_number }, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchWithEmptyArgs(self: PubClient, comptime T: type, method: EthereumRpcMethods) !T {
    const Params = std.meta.Tuple(&[_]type{});
    const request: EthereumRequest(Params) = .{ .params = .{}, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.value;
}

fn fetchBlock(self: PubClient, request: anytype) !block.Block {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(EthereumResponse(block.Block), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            @panic(result.@"error".message);
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

// test "Placeholder" {
//     const pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545");
//     defer pub_client.deinit();
//
//     const block_req = try pub_client.getTransactionByHash("0x84ea9218876a33cac46673308427ddfe3c7819e9f4353a5a4b8557332ab76cf6");
//
//     std.debug.print("Foooo: {}\n\n\n", .{block_req});
// }
