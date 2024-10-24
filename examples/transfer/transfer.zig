const args_parser = @import("zabi-utils").args;
const std = @import("std");
const clients = @import("zabi-clients");

const Wallet = clients.wallet.Wallet(.websocket);

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

    var wallet = try Wallet.init(parsed.priv_key, .{
        .allocator = gpa.allocator(),
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .chain_id = .sepolia,
            .base_fee_multiplier = 3.2,
        },
    }, true);
    defer wallet.deinit();

    const hash = try wallet.sendTransaction(.{ .type = .london, .to = try @import("zabi-utils").utils.addressToBytes("0x0000000000000000000000000000000000000000"), .value = 42069 });
    defer hash.deinit();

    const receipt = try wallet.waitForTransactionReceipt(hash.response, 0);
    defer receipt.deinit();

    std.debug.print("Transaction receipt: {}", .{receipt.response});
}
