const generator = @import("generator.zig");
const std = @import("std");
const types = @import("types/root.zig");

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

pub const ServerConfig = struct {
    ip_address: ?[]const u8 = null,
    port: ?u16 = null,
    seed: u64 = 69,
};

address: std.net.Address,

seed: u64,

pub fn init(opts: ServerConfig) !Server {
    const address = opts.ip_address orelse "127.0.0.1";
    const port = opts.port orelse 6969;

    const parsed_address = try std.net.Address.parseIp(address, port);

    return .{
        .address = parsed_address,
        .seed = opts.seed,
    };
}

pub fn listenToOneRequest(self: Server, comptime buffer_size: comptime_int, allocator: Allocator) !void {
    var buffer: [buffer_size]u8 = undefined;

    var server = try self.address.listen(.{
        .reuse_port = true,
        .reuse_address = true,
    });
    defer server.deinit();

    const conn = try server.accept();

    var http = HttpServer.init(conn, &buffer);

    var req = try http.receiveHead();
    switch (req.head.method) {
        .POST => {
            var header = req.iterateHeaders();

            while (header.next()) |head| {
                if (std.mem.eql(u8, "application/json", head.value)) {
                    return self.handleRequest(allocator, &req);
                }
            } else return error.InvalidHeader;
        },
        else => return error.MethodNotSupported,
    }
}

fn handleRequest(self: Server, allocator: Allocator, req: *HttpServer.Request) !void {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    const reader = try req.reader();
    try reader.readAllArrayList(&list, 1024 * 1024);

    const slice = try list.toOwnedSlice();
    defer allocator.free(slice);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, slice, .{ .ignore_unknown_fields = true });
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
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse([32]u8), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_accounts,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse([]const [20]u8), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_createAccessList,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(AccessListResult), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getProof,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(ProofResult), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getBlockByNumber,
        .eth_getBlockByHash,
        .eth_getUncleByBlockHashAndIndex,
        .eth_getUncleByBlockNumberAndIndex,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(Block), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getTransactionReceipt,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(TransactionReceipt), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getTransactionByHash,
        .eth_getTransactionByBlockHashAndIndex,
        .eth_getTransactionByBlockNumberAndIndex,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(Transaction), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_feeHistory,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(FeeHistory), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_call,
        .eth_getCode,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse([]u8), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_unsubscribe,
        .eth_uninstallFilter,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(bool), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getLogs,
        .eth_getFilterLogs,
        .eth_getFilterChanges,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(Logs), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_getBalance,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(u256), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
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
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(u64), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        .eth_newFilter,
        .eth_newBlockFilter,
        .eth_newPendingTransactionFilter,
        .eth_subscribe,
        => {
            const generated = try generator.generateRandomData(EthereumRpcResponse(u128), allocator, self.seed, .{
                .slice_size = 5,
                .use_default_values = true,
            });
            defer generated.deinit();

            const json_slice = try std.json.stringifyAlloc(allocator, generated.generated, .{});
            defer allocator.free(json_slice);

            try req.respond(json_slice, .{});
        },
        else => return error.UnsupportedRpcMethod,
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var server = try Server.init(.{});

    while (true) {
        try server.listenToOneRequest(8192, gpa.allocator());
    }
}
