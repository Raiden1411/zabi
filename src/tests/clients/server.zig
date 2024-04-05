const generator = @import("../generator.zig");
const std = @import("std");
const types = @import("../../types/root.zig");

const AccessListResult = types.transactions.AccessListResult;
const Allocator = std.mem.Allocator;
const Block = types.block.Block;
const EthereumRpcResponse = types.ethereum.EthereumRpcResponse;
const EthereumRpcMethods = types.ethereum.EthereumRpcMethods;
const FeeHistory = types.transactions.FeeHistory;
const HttpServer = std.http.Server;
const Logs = types.log.Logs;
const ProofResult = types.proof.ProofResult;
const Transaction = types.transactions.Transaction;
const TransactionReceipt = types.transactions.TransactionReceipt;

const Server = @This();

const server_log = std.log.scoped(.server);

pub const ServerConfig = struct {
    /// Must follow ip address rules.
    ip_address: []const u8 = "127.0.0.1",
    /// The port to connect to.
    port: u16 = 6969,
    /// The seed for the PRNG randomizer.
    seed: u64 = 69,
    /// The size of the buffer for the http server to use
    buffer_size: u64 = 8192,
    /// The allocator that creates the server pointer
    /// and takes care of any allocations.
    allocator: Allocator,
};

/// The ip address for the server to connect to.
address: std.net.Address,
/// The seed used to generate random data.
seed: u64,
/// The socket server to that the server uses
server: *std.net.Server,
/// The allocator to manage all memory
allocator: Allocator,
/// buffer size for the http server to use.
buffer_size: u64,

/// Starts a server instance and
/// readys the socket for accepting connections.
pub fn init(self: *Server, opts: ServerConfig) !void {
    const server = try opts.allocator.create(std.net.Server);
    errdefer opts.allocator.destroy(server);

    const parsed_address = try std.net.Address.parseIp(opts.ip_address, opts.port);

    server.* = try parsed_address.listen(.{
        .reuse_port = true,
        .reuse_address = true,
    });

    self.* = .{
        .address = parsed_address,
        .seed = opts.seed,
        .server = server,
        .allocator = opts.allocator,
        .buffer_size = opts.buffer_size,
    };
}
/// Closes the connection and destroys any pointers.
pub fn deinit(self: *Server) void {
    self.server.deinit();

    self.allocator.destroy(self.server);
    self.* = undefined;
}
/// Accepts a single request.
/// This blocks until a connection is accepted.
///
/// Only POST requests are accepted and "application/json" headers are
/// allowed. Will always send error 429.
pub fn listenButSendOnlyError429Response(self: *Server) !void {
    const buffer = try self.allocator.alloc(u8, self.buffer_size);

    const conn = try self.server.accept();

    var http = HttpServer.init(conn, buffer);

    var req = try http.receiveHead();
    switch (req.head.method) {
        .POST => {
            try req.respond(
                "Too many requests. You need to wait a couple of ms and try again",
                .{ .status = .too_many_requests },
            );
        },
        else => return error.MethodNotSupported,
    }
}
/// Accepts a single request.
/// This blocks until a connection is accepted.
///
/// Only POST requests are accepted and "application/json" headers are
/// allowed.
pub fn listenToOneRequest(self: *Server) !void {
    const buffer = try self.allocator.alloc(u8, self.buffer_size);

    const conn = try self.server.accept();

    var http = HttpServer.init(conn, buffer);

    var req = try http.receiveHead();
    switch (req.head.method) {
        .POST => {
            var header = req.iterateHeaders();

            while (header.next()) |head| {
                if (std.mem.eql(u8, "application/json", head.value)) {
                    return self.handleRequest(&req);
                }
            } else return error.InvalidHeader;
        },
        else => return error.MethodNotSupported,
    }
}
/// Handles and mimics a json rpc response from a JSON-RPC server.
/// Uses the custom data generator to produce the response.
fn handleRequest(self: *Server, req: *HttpServer.Request) !void {
    var list = std.ArrayList(u8).init(self.allocator);
    errdefer list.deinit();

    const reader = try req.reader();
    try reader.readAllArrayList(&list, 1024 * 1024);

    const slice = try list.toOwnedSlice();
    defer self.allocator.free(slice);

    server_log.debug("Parsing request: {s}", .{slice});

    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, slice, .{ .ignore_unknown_fields = true }) catch {
        try req.respond("Invalid json formating.", .{ .status = .bad_request });

        return;
    };
    defer parsed.deinit();

    const method = blk: {
        const method = parsed.value.object.get("method") orelse return error.InvalidResponse;

        if (method != .string)
            return error.InvalidResponse;

        const as_enum = std.meta.stringToEnum(EthereumRpcMethods, method.string) orelse return error.InvalidRpcMethod;

        break :blk as_enum;
    };

    switch (method) {
        .eth_sendRawTransaction,
        .eth_getStorageAt,
        => try self.sendResponse([32]u8, req),
        .eth_accounts,
        => try self.sendResponse([]const [20]u8, req),
        .eth_createAccessList,
        => try self.sendResponse(AccessListResult, req),
        .eth_getProof,
        => try self.sendResponse(ProofResult, req),
        .eth_getBlockByNumber,
        .eth_getBlockByHash,
        .eth_getUncleByBlockHashAndIndex,
        .eth_getUncleByBlockNumberAndIndex,
        => try self.sendResponse(Block, req),
        .eth_getTransactionReceipt,
        => try self.sendResponse(TransactionReceipt, req),
        .eth_getTransactionByHash,
        .eth_getTransactionByBlockHashAndIndex,
        .eth_getTransactionByBlockNumberAndIndex,
        => try self.sendResponse([32]u8, req),
        .eth_feeHistory,
        => try self.sendResponse(FeeHistory, req),
        .eth_call,
        .eth_getCode,
        => try self.sendResponse([]u8, req),
        .eth_unsubscribe,
        .eth_uninstallFilter,
        => try self.sendResponse(bool, req),
        .eth_getLogs,
        .eth_getFilterLogs,
        .eth_getFilterChanges,
        => try self.sendResponse(Logs, req),
        .eth_getBalance,
        => try self.sendResponse(u256, req),
        .eth_chainId,
        .eth_gasPrice,
        .eth_estimateGas,
        .eth_blobBaseFee,
        .eth_blockNumber,
        .eth_getUncleCountByBlockHash,
        .eth_getUncleCountByBlockNumber,
        .eth_getTransactionCount,
        .eth_maxPriorityFeePerGas,
        .eth_getBlockTransactionCountByHash,
        .eth_getBlockTransactionCountByNumber,
        => try self.sendResponse(u64, req),
        .eth_newFilter,
        .eth_newBlockFilter,
        .eth_newPendingTransactionFilter,
        .eth_subscribe,
        => try self.sendResponse(u128, req),
        else => return error.UnsupportedRpcMethod,
    }
}
/// Sends the response back to the user.
fn sendResponse(self: *Server, comptime T: type, req: *HttpServer.Request) !void {
    const generated = try generator.generateRandomData(EthereumRpcResponse(T), self.allocator, self.seed, .{
        .slice_size = 6,
        .use_default_values = true,
    });
    defer generated.deinit();

    const json_slice = try std.json.stringifyAlloc(self.allocator, generated.generated, .{});
    defer self.allocator.free(json_slice);

    try req.respond(json_slice, .{});
}
