const generator = @import("../utils/generator.zig");
const pipe = @import("../utils/pipe.zig");
const std = @import("std");
const types = @import("../types/root.zig");

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
const SyncStatus = types.sync.SyncStatus;

const Server = @This();

const server_log = std.log.scoped(.server);

pub const ServerConfig = struct {
    /// Must follow ip address rules.
    ip_address: []const u8 = "127.0.0.1",
    /// The port to connect to.
    port: u16 = 6969,
    /// The seed for the PRNG randomizer.
    seed: u64 = 69,
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
/// Mutex used by this server to handle request in seperate thread.
mutex: std.Thread.Mutex,

/// Starts a server instance and
/// readys the socket for accepting connections.
pub fn init(self: *Server, opts: ServerConfig) !void {
    const server = try opts.allocator.create(std.net.Server);
    errdefer opts.allocator.destroy(server);

    const parsed_address = try std.net.Address.parseIp(opts.ip_address, opts.port);

    server.* = try parsed_address.listen(.{
        .reuse_address = true,
    });

    self.* = .{
        .address = parsed_address,
        .seed = opts.seed,
        .server = server,
        .allocator = opts.allocator,
        .mutex = .{},
    };
}
/// Closes the connection and destroys any pointers.
pub fn deinit(self: *Server) void {
    self.mutex.lock();

    self.server.deinit();

    self.allocator.destroy(self.server);
}
/// Create the listen loop to handle http requests.
pub fn listen(self: *Server, send_error_429: bool) !void {
    var buffer: [8192]u8 = undefined;

    accept: while (true) {
        const conn = try self.server.accept();

        var http = HttpServer.init(conn, &buffer);

        while (http.state == .ready) {
            var req = http.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => continue :accept,
                else => {
                    server_log.debug("Failed to get request. Error: {s}", .{@errorName(err)});
                    continue :accept;
                },
            };

            switch (req.head.method) {
                .POST => if (send_error_429) try req.respond(
                    "Too many requests. Try again in a couple of ms",
                    .{ .status = .too_many_requests },
                ) else {
                    self.handleRequest(&req) catch {
                        try req.respond("Internal server error", .{ .status = .internal_server_error });
                    };
                },
                else => try req.respond("Method not allowed", .{ .status = .method_not_allowed }),
            }
        }
    }
}
/// Accepts a single request.
/// This blocks until a connection is accepted.
///
/// Only POST requests are accepted and "application/json" headers are
/// allowed. Will always send error 429.
pub fn listenButSendOnlyError429Response(self: *Server) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var buffer: [8192]u8 = undefined;

    server_log.debug("Waiting to receive connection.", .{});
    const conn = try self.server.accept();

    var http = HttpServer.init(conn, &buffer);

    server_log.debug("Got connection. Parsing the request", .{});
    var req = try http.receiveHead();

    switch (req.head.method) {
        .POST => try req.respond(
            "Too many requests. Try again in a couple of ms",
            .{ .status = .too_many_requests },
        ),
        else => try req.respond("Method not allowed", .{ .status = .method_not_allowed }),
    }
}
/// Accepts a single request.
/// This blocks until a connection is accepted.
///
/// Only POST requests are accepted and "application/json" headers are
/// allowed.
pub fn listenToOneRequest(self: *Server) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var buffer: [8192]u8 = undefined;

    const conn = try self.server.accept();

    var http = HttpServer.init(conn, &buffer);

    var req = try http.receiveHead();
    switch (req.head.method) {
        .POST => try self.handleRequest(&req),
        else => try req.respond("Method not allowed", .{ .status = .method_not_allowed }),
    }
}
/// Listen to a request in a seperate thread.
///
/// Control if you would like to send errors 429.
pub fn listenOnceInSeperateThread(self: *Server, send_error_429: bool) !void {
    pipe.maybeIgnoreSigpipe();

    const thread = if (send_error_429)
        try std.Thread.spawn(.{}, listenButSendOnlyError429Response, .{self})
    else
        try std.Thread.spawn(.{}, listenToOneRequest, .{self});

    thread.detach();
}
/// Creates the server loop in a seperate thread.
///
/// Control if you would like to send errors 429.
pub fn listenLoopInSeperateThread(self: *Server, send_error_429: bool) !void {
    pipe.maybeIgnoreSigpipe();

    const thread = try std.Thread.spawn(.{}, listen, .{ self, send_error_429 });
    thread.detach();
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
        const method = parsed.value.object.get("method") orelse {
            try req.respond("Missing method field.", .{ .status = .bad_request });

            return;
        };

        if (method != .string) {
            try req.respond("Incorrect method type. Expected string", .{ .status = .bad_request });

            return;
        }

        const as_enum = std.meta.stringToEnum(EthereumRpcMethods, method.string) orelse {
            try req.respond("Invalid RPC Method", .{ .status = .bad_request });

            return;
        };

        break :blk as_enum;
    };

    return switch (method) {
        .eth_sendRawTransaction,
        .eth_getStorageAt,
        .web3_sha3,
        => self.sendResponse([32]u8, req),
        .eth_accounts,
        => self.sendResponse([]const [20]u8, req),
        .eth_createAccessList,
        => self.sendResponse(AccessListResult, req),
        .eth_getProof,
        => self.sendResponse(ProofResult, req),
        .eth_getBlockByNumber,
        .eth_getBlockByHash,
        .eth_getUncleByBlockHashAndIndex,
        .eth_getUncleByBlockNumberAndIndex,
        => self.sendResponse(Block, req),
        .eth_getTransactionReceipt,
        => self.sendResponse(TransactionReceipt, req),
        .eth_getTransactionByHash,
        .eth_getTransactionByBlockHashAndIndex,
        .eth_getTransactionByBlockNumberAndIndex,
        => self.sendResponse(Transaction, req),
        .eth_feeHistory,
        => self.sendResponse(FeeHistory, req),
        .eth_call,
        .eth_getCode,
        .eth_getRawTransactionByHash,
        => self.sendResponse([]u8, req),
        .eth_unsubscribe,
        .eth_uninstallFilter,
        .net_listening,
        => self.sendResponse(bool, req),
        .eth_getLogs,
        .eth_getFilterLogs,
        .eth_getFilterChanges,
        => self.sendResponse(Logs, req),
        .eth_getBalance,
        => self.sendResponse(u256, req),
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
        .net_version,
        .net_peerCount,
        .eth_protocolVersion,
        => self.sendResponse(u64, req),
        .eth_newFilter,
        .eth_newBlockFilter,
        .eth_newPendingTransactionFilter,
        .eth_subscribe,
        => self.sendResponse(u128, req),
        .web3_clientVersion,
        => self.sendResponse([]const u8, req),
        .eth_syncing,
        => self.sendResponse(SyncStatus, req),
        else => error.UnsupportedRpcMethod,
    };
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
