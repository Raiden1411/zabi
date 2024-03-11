const std = @import("std");
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
    try wallet.init(private_key, .{ .allocator = gpa.allocator(), .uri = uri });
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");
    std.debug.print("Ethereum message: {s}\n", .{try message.toHex(wallet.allocator)});
}
