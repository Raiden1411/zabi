const args_parser = zabi.args;
const std = @import("std");
const zabi = @import("zabi");

pub const CliOptions = struct {
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, &iter);

    const uri = try std.Uri.parse(parsed.url);

    var socket: zabi.clients.WebSocket = undefined;
    defer socket.deinit();

    try socket.init(.{ .uri = uri, .allocator = gpa.allocator() });

    const id = try socket.watchTransactions();
    defer id.deinit();

    std.debug.print("Sub id: 0x{x}\n", .{id.response});
    // There is currently a bug on the tls client that will cause index out of bound errors
    // https://github.com/ziglang/zig/issues/15226
    // Make sure that for now the data you are using is not big enough to cause these crashes.
    while (true) {
        const event = try socket.getPendingTransactionsSubEvent();
        defer event.deinit();

        const hash = event.response.params.result;
        const transaction = socket.getTransactionByHash(hash) catch |err| switch (err) {
            error.TransactionNotFound => continue,
            else => return err,
        };
        defer transaction.deinit();

        switch (transaction.response) {
            .london => |tx_london| {
                if (tx_london.to) |to| {
                    if (std.mem.eql(u8, &to, &try zabi.utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"))) {
                        std.debug.print("Found usdc transaction in the value of {d} wei\n", .{tx_london.value});
                        break;
                    }
                }
            },
            else => {},
        }
    }

    const unsubed = try socket.unsubscribe(id.response);
    defer unsubed.deinit();
}
