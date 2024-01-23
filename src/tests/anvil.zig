const std = @import("std");

const Anvil = @This();

fork_url: []const u8,
alloc: std.mem.Allocator,
result: std.ChildProcess,
thread: std.Thread,
localhost: std.Uri,
pooling_interval: u64,
stream: std.net.Stream,

pub fn init(self: *Anvil, alloc: std.mem.Allocator, pooling_interval: u64) !void {
    self.* = .{
        .alloc = alloc,
        .localhost = try std.Uri.parse("http://localhost:8545/"),
        .thread = try std.Thread.spawn(.{}, start, .{self}),
        .pooling_interval = pooling_interval,
        .fork_url = "https://eth-mainnet.alchemyapi.io/v2/C3JEvfW6VgtqZQa-Qp1E-2srEiIc02sD",
        .stream = undefined,
        .result = undefined,
    };
}

pub fn deinit(self: *Anvil) void {
    _ = self.result.kill() catch |err| {
        std.io.getStdErr().writer().writeAll(@errorName(err)) catch {};
    };
    self.thread.detach();
}

pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", self.fork_url, "--fork-block-number", "19062632", "--port", "8545" }, self.alloc);
    result.stdin_behavior = .Close;
    result.stdout_behavior = .Close;
    result.stderr_behavior = .Close;

    try result.spawn();

    self.result = result;
}

pub fn waitUntilReady(alloc: std.mem.Allocator, pooling_interval: u64) !void {
    var retry: u32 = 0;
    var stream: std.net.Stream = undefined;
    while (true) {
        if (retry > 20) break;
        stream = std.net.tcpConnectToHost(alloc, "127.0.0.1", 8545) catch {
            std.time.sleep(pooling_interval * std.time.ns_per_ms);
            retry += 1;
            continue;
        };

        break;
    }

    _ = try stream.write("PONG");
    stream.close();
}
