const std = @import("std");
const zabi = @import("zabi");
const Wallet = zabi.wallet.Wallet(.http);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var iter = try std.process.ArgIterator.initWithAllocator(gpa.allocator());
    defer iter.deinit();

    _ = iter.skip();

    var wallet = try Wallet.init(gpa.allocator(), iter.next().?, iter.next().?, .ethereum);
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage(wallet.alloc, "Hello World");
    std.debug.print("Ethereum message: {s}\n", .{try message.toHex(wallet.alloc)});
}
