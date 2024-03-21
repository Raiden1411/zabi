const std = @import("std");
const utils = zabi.utils;
const zabi = @import("zabi");

const Wallet = zabi.clients.wallet.Wallet(.http);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var iter = try std.process.ArgIterator.initWithAllocator(gpa.allocator());
    defer iter.deinit();

    _ = iter.skip();

    const private_key = iter.next().?;
    const host_url = iter.next().?;

    const uri = try std.Uri.parse(host_url);

    var wallet: Wallet = undefined;
    try wallet.init(private_key, .{ .allocator = gpa.allocator(), .uri = uri, .chain_id = .sepolia, .pooling_interval = 12_000 });
    defer wallet.deinit();

    const hash = try wallet.sendTransaction(.{ .type = .london, .to = try utils.addressToBytes("0x0000000000000000000000000000000000000000"), .value = 42069 });
    defer hash.deinit();

    const receipt = try wallet.waitForTransactionReceipt(hash.response, 0);
    defer receipt.deinit();

    std.debug.print("Transaction receipt: {}", .{receipt.response});
}
