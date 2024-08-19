const args_parser = zabi.args;
const std = @import("std");
const zabi = @import("zabi");
const Wallet = zabi.clients.wallet.Wallet(.http);

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    var wallet = try Wallet.init(parsed.priv_key, .{ .allocator = gpa.allocator(), .uri = uri });
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");

    const hexed = try message.toHex(wallet.allocator);
    defer gpa.allocator().free(hexed);

    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
