const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const WebProvider = clients.Provider.WebsocketProvider;

pub const CliOptions = struct {
    url: []const u8,
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    var threaded_io: std.Io.Threaded = .init(gpa.allocator(), .{});
    defer threaded_io.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    var socket = try WebProvider.init(.{
        .network_config = .{ .endpoint = .{ .uri = uri } },
        .io = threaded_io.io(),
        .allocator = gpa.allocator(),
    });
    defer socket.deinit();

    try socket.readLoopSeperateThread();

    const id = try socket.provider.watchTransactions();
    defer id.deinit();

    std.debug.print("Sub id: 0x{x}\n", .{id.response});
    while (true) {
        const event = try socket.getPendingTransactionsSubEvent();
        defer event.deinit();

        const hash = event.response.params.result;
        const transaction = socket.provider.getTransactionByHash(hash) catch |err| switch (err) {
            error.TransactionNotFound => continue,
            else => return err,
        };
        defer transaction.deinit();

        switch (transaction.response) {
            .london => |tx_london| {
                if (tx_london.to) |to| {
                    const casted_to: u160 = @bitCast(to);
                    const expected: u160 = comptime @bitCast(@import("zabi").utils.utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable);

                    if (casted_to == expected) {
                        std.debug.print("Found usdc transaction in the value of {d} wei\n", .{tx_london.value});
                        break;
                    }
                }
            },
            else => {},
        }
    }

    const unsubed = try socket.provider.unsubscribe(id.response);
    defer unsubed.deinit();
}
