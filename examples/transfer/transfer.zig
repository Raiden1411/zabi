const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const WebProvider = clients.Provider.WebsocketProvider;
const Wallet = clients.Wallet;

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var threaded_io: std.Io.Threaded = .init(gpa.allocator());
    defer threaded_io.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    var socket = try WebProvider.init(.{
        .allocator = gpa.allocator(),
        .io = threaded_io.io(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .chain_id = .sepolia,
            .base_fee_multiplier = 3.2,
        },
    });
    defer socket.deinit();

    try socket.readLoopSeperateThread();

    var wallet = try Wallet.init(parsed.priv_key, gpa.allocator(), &socket.provider, true);
    defer wallet.deinit();

    const hash = try wallet.sendTransaction(.{
        .type = .london,
        .to = comptime @import("zabi").utils.utils.addressToBytes("0x0000000000000000000000000000000000000000") catch unreachable,
        .value = 42069,
    });
    defer hash.deinit();

    const receipt = try wallet.rpc_client.waitForTransactionReceipt(hash.response, 0);
    defer receipt.deinit();

    var buffer: [4096]u8 = undefined;
    var buffer_stream = std.Io.Writer.fixed(&buffer);
    try std.json.Stringify.value(receipt.response, .{}, &buffer_stream);

    std.debug.print("Transaction receipt: {s}", .{buffer_stream.buffered()});
}
