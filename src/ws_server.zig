const args_parse = @import("tests/args.zig");
const std = @import("std");
const ws_server = @import("tests/clients/ws_server.zig");
const ws = @import("ws");

const WsContext = ws_server.WsContext;
const WsHandler = ws_server.WsHandler;

const CliOptions = struct {
    seed: u64 = 69,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const parsed = args_parse.parseArgs(CliOptions, gpa.allocator(), &args);

    // this is the instance of your "global" struct to pass into your handlers
    var context: WsContext = .{ .allocator = gpa.allocator(), .seed = parsed.seed };

    try ws.listen(WsHandler, gpa.allocator(), &context, .{
        .port = 6970,
        .handshake_max_size = 1024,
        .handshake_pool_count = 10,
        .handshake_timeout_ms = 3000,
        .buffer_size = 8192,
        .max_size = comptime std.math.maxInt(u24),
        .address = "127.0.0.1",
    });
}
