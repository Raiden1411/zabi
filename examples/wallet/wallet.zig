const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const HttpProvider = clients.Provider.HttpProvider;
const Wallet = clients.Wallet;

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var threaded_io: std.Io.Threaded = .init(init.gpa, .{
        .environ = init.minimal.environ,
    });
    defer threaded_io.deinit();

    var iter = init.minimal.args.iterate();
    const parsed = args_parser.parseArgs(CliOptions, init.gpa, &iter);

    const uri = try std.Uri.parse(parsed.url);

    var provider = try HttpProvider.init(.{
        .allocator = init.gpa,
        .io = threaded_io.io(),
        .network_config = .{ .endpoint = .{ .uri = uri } },
    });
    defer provider.deinit();

    var wallet = try Wallet.init(parsed.priv_key, init.gpa, &provider.provider, false);
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");

    const hexed = try message.toHex(wallet.allocator);
    defer init.gpa.free(hexed);

    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
