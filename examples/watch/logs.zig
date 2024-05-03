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

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    var socket: zabi.clients.WebSocket = undefined;
    defer socket.deinit();

    try socket.init(.{ .uri = uri, .allocator = gpa.allocator() });

    const id = try socket.watchLogs(.{
        .address = try zabi.utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        .topics = &.{@constCast(&try zabi.utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"))},
    });
    defer id.deinit();

    std.debug.print("Sub id: 0x{x}\n", .{id.response});
    // There is currently a bug on the tls client that will cause index out of bound errors
    // https://github.com/ziglang/zig/issues/15226
    // Make sure that for now the data you are using is not big enough to cause these crashes.
    while (true) {
        const event = try socket.getLogsSubEvent();
        defer event.deinit();

        const value = try zabi.decoding.abi_decoder.decodeAbiParameters(gpa.allocator(), &.{
            .{ .type = .{ .uint = 256 }, .name = "tokenId" },
        }, event.response.params.result.data, .{});

        const topics = try zabi.decoding.logs_decoder.decodeLogsComptime(&.{
            .{ .type = .{ .address = {} }, .name = "from", .indexed = true },
            .{ .type = .{ .address = {} }, .name = "to", .indexed = true },
        }, event.response.params.result.topics);

        std.debug.print("Transfer event found. Value transfered: {d} dollars\n", .{value[0] / 1000000});
        std.debug.print("From: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&topics[1])});
        std.debug.print("To: 0x{s}\n", .{std.fmt.fmtSliceHexLower(&topics[2])});
    }

    const unsubed = try socket.unsubscribe(id.response);
    defer unsubed.deinit();
}
