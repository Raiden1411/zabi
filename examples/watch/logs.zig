const args_parser = @import("zabi").utils.args;
const clients = @import("zabi").clients;
const decoder = @import("zabi").decoding;
const std = @import("std");

const WebProvider = clients.Provider.WebsocketProvider;

pub const CliOptions = struct {
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

    var socket = try WebProvider.init(.{
        .network_config = .{ .endpoint = .{ .uri = uri } },
        .io = threaded_io.io(),
        .allocator = init.gpa,
    });
    defer socket.deinit();

    try socket.readLoopSeperateThread();

    const id = try socket.provider.watchLogs(.{
        .address = try @import("zabi").utils.utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        .topics = &.{@constCast(&try @import("zabi").utils.utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"))},
    });
    defer id.deinit();

    std.debug.print("Sub id: 0x{x}\n", .{id.response});
    while (true) {
        const event = try socket.getLogsSubEvent();
        defer event.deinit();

        const value = try decoder.abi_decoder.decodeAbiParameter(u256, init.gpa, event.response.params.result.data, .{});
        defer value.deinit();

        const topics = try decoder.logs_decoder.decodeLogs(struct { [32]u8, [20]u8, [20]u8 }, event.response.params.result.topics, .{});

        std.debug.print("Transfer event found. Value transfered: {d} dollars\n", .{value.result / 1000000});
        std.debug.print("From: 0x{x}\n", .{&topics[1]});
        std.debug.print("To: 0x{x}\n", .{&topics[2]});
    }

    const unsubed = try socket.provider.unsubscribe(id.response);
    defer unsubed.deinit();
}
