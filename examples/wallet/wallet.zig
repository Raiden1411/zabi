const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const HttpProvider = clients.Provider.HttpProvider;
const Wallet = clients.Wallet;

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var threaded_io: std.Io.Threaded = .init(gpa.allocator(), .{});
    defer threaded_io.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);
    var provider = try HttpProvider.init(.{
        .allocator = gpa.allocator(),
        .io = threaded_io.io(),
        .network_config = .{ .endpoint = .{ .uri = uri } },
    });
    defer provider.deinit();

    var wallet = try Wallet.init(parsed.priv_key, gpa.allocator(), &provider.provider, false);
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");

    const hexed = try message.toHex(wallet.allocator);
    defer gpa.allocator().free(hexed);

    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
