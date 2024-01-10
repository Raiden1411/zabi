const block = @import("block.zig");
const http = std.http;
const meta = @import("meta/meta.zig");
const std = @import("std");
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

        pub usingnamespace if (@typeInfo(T) == .Int) meta.RequestParser(@This()) else {};
    };
}

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

pub fn getGasPrice(self: PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_gasPrice);
}

pub fn getAccounts(self: PubClient) ![]const []const u8 {
    return self.fetchWithEmptyArgs([]const []const u8, .eth_accounts);
}

pub fn getBlockNumber(self: PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_blockNumber);
}

pub fn getBlockTransactionCountByHash(self: PubClient, block_hash: []const u8) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getBlockTransactionCountByHash);
}

pub fn getBlockTransactionCountByNumber(self: PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getBlockTransactionCountByNumber);
}

pub fn getUncleCountByBlockHash(self: PubClient, block_hash: []const u8) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getUncleCountByBlockHash);
}

pub fn getUncleCountByBlockNumber(self: PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getUncleCountByBlockNumber);
}

pub fn getAddressBalance(self: PubClient, opts: block.BalanceRequest) !u256 {
    return self.fetchByAddress(u256, opts, .eth_getBalance);
}

pub fn getAddressTransactionCount(self: PubClient, opts: block.BalanceRequest) !usize {
    return self.fetchByAddress(usize, opts, .eth_getTransactionCount);
}

pub fn getContractCode(self: PubClient, opts: block.BalanceRequest) ![]const u8 {
    return self.fetchByAddress([]const u8, opts, .eth_getCode);
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

    const Params = std.meta.Tuple(&[_]type{ []const u8, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash };

    return self.fetchBlock(request);
}

fn fetchByBlockNumber(self: PubClient, opts: block.BlockNumberRequest, method: EthereumRpcMethods) !usize {
    const tag: block.BalanceRequest = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{[]const u8});
    const params: Params = .{block_number};

    const request: EthereumRequest(Params) = .{ .params = params, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(usize), self.alloc, req.body.?, .{});

    return parsed.result;
}

fn fetchByBlockHash(self: PubClient, block_hash: []const u8, method: EthereumRpcMethods) !usize {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{[]const u8});
    const params: Params = .{block_hash};

    const request: EthereumRequest(Params) = .{ .params = params, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(usize), self.alloc, req.body.?, .{});

    return parsed.result;
}

fn fetchByAddress(self: PubClient, comptime T: type, opts: block.BalanceRequest, method: EthereumRpcMethods) !T {
    if (!try utils.isAddress(self.alloc, opts.address)) return error.InvalidAddress;
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ []const u8, []const u8 });
    const request: EthereumRequest(Params) = .{ .params = .{ opts.address, block_number }, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(T), self.alloc, req.body.?, .{});

    return parsed.result;
}

fn fetchWithEmptyArgs(self: PubClient, comptime T: type, method: EthereumRpcMethods) !T {
    const Params = std.meta.Tuple(&[_]type{});
    const request: EthereumRequest(Params) = .{ .params = .{}, .method = method };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(T), self.alloc, req.body.?, .{});

    return parsed.value;
}

fn fetchBlock(self: PubClient, request: anytype) !block.Block {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = try std.json.parseFromSliceLeaky(EthereumResponse(block.Block), self.alloc, req.body.?, .{});

    return parsed.result;
}

test "Placeholder" {
    const pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545");
    defer pub_client.deinit();

    const block_req = try pub_client.getAddressTransactionCount(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });

    std.debug.print("Foooo: {d}\n\n\n", .{block_req});
}
