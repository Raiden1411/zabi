const args_parser = @import("zabi").utils.args;
const clients = @import("zabi").clients;
const decoder = @import("zabi").decoding;
const std = @import("std");

const WebSocket = clients.WebSocket;

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

    var socket = try WebSocket.init(.{
        .network_config = .{ .endpoint = .{ .uri = uri } },
        .allocator = gpa.allocator(),
    });
    defer socket.deinit();

    const id = try socket.watchLogs(.{
        .address = try @import("zabi").utils.utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        .topics = &.{@constCast(&try @import("zabi").utils.utils.hashToBytes("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"))},
    });
    defer id.deinit();

    std.debug.print("Sub id: 0x{x}\n", .{id.response});
    while (true) {
        const event = try socket.getLogsSubEvent();
        defer event.deinit();

        const value = try decoder.abi_decoder.decodeAbiParameter(u256, gpa.allocator(), event.response.params.result.data, .{});
        defer value.deinit();

        const topics = try decoder.logs_decoder.decodeLogs(struct { [32]u8, [20]u8, [20]u8 }, event.response.params.result.topics, .{});

        std.debug.print("Transfer event found. Value transfered: {d} dollars\n", .{value.result / 1000000});
        std.debug.print("From: 0x{x}\n", .{&topics[1]});
        std.debug.print("To: 0x{x}\n", .{&topics[2]});
    }

    const unsubed = try socket.unsubscribe(id.response);
    defer unsubed.deinit();
}
