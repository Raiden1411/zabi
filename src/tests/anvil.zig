// const meta = @import("../meta/ethereum.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const Anvil = @This();

pub const StartUpOptions = struct {
    /// Allocator to use to create the ChildProcess and other allocations
    alloc: Allocator,
    /// Fork url for anvil to fork from
    fork_url: []const u8,
    /// Fork block number to use
    block_number_fork: u64 = 19062632,
    /// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
    retry_count: u8 = 5,
    /// The interval to retry the connection. This will get multiplied in ns_per_ms.
    pooling_interval: u64 = 2_000,
    /// The localhost address.
    localhost: []const u8 = "http://127.0.0.1:8545/",
};

/// Allocator to use to create the ChildProcess and other allocations
alloc: std.mem.Allocator,
/// Fork block number to use
block_number_fork: u64,
/// The localhost address uri.
localhost: std.Uri,
/// Fork url for anvil to fork from
fork_url: []const u8,
/// The interval to retry the connection. This will get multiplied in ns_per_ms.
pooling_interval: u64,
/// The socket connection to anvil. Use `connectToAnvil` to populate this.
stream: std.net.Stream,
/// The ChildProcess result. This contains all related commands.
result: std.ChildProcess,
/// Retry count for failed connections to anvil. The process takes some ms to start so this is necessary
retry_count: u8,
/// The theared that gets spawn on init for the ChildProcess so that we don't block the main thread.
// thread: std.Thread,

pub fn init(self: *Anvil, opts: StartUpOptions) !void {
    self.* = .{
        .alloc = opts.alloc,
        .fork_url = opts.fork_url,
        .localhost = try std.Uri.parse(opts.localhost),
        .pooling_interval = opts.pooling_interval,
        .retry_count = opts.retry_count,
        .block_number_fork = opts.block_number_fork,
        .thread = try std.Thread.spawn(.{}, start, .{self}),
        .stream = undefined,
        .result = undefined,
    };
}

/// Kills the anvil process and closes any connections.
pub fn deinit(self: *Anvil) void {
    _ = self.result.kill() catch |err| {
        std.io.getStdErr().writer().writeAll(@errorName(err)) catch {};
    };
    self.stream.close();
    self.thread.detach();
}

/// Start the child process. Use this with init if you want to use this in a seperate theread.
pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", self.fork_url, "--fork-block-number", self.block_number_fork, "--port", self.localhost.port.? }, self.alloc);
    result.stdin_behavior = .Pipe;
    result.stdout_behavior = .Pipe;
    result.stderr_behavior = .Pipe;

    try result.spawn();

    self.result = result;
}

/// Use this to connect to the spawned anvil instance.
pub fn connectToAnvil(self: *Anvil) !void {
    var retry: u32 = 0;
    while (true) {
        if (retry > self.retry_count) break;

        self.stream = std.net.tcpConnectToHost(self.alloc, "wss://eth-mainnet.g.alchemy.com/v2/EYebpRd8FEJ0WYXQ3Afl6O85T8vo6XvO", 36596) catch {
            std.time.sleep(self.pooling_interval * std.time.ns_per_ms);
            retry += 1;
            continue;
        };

        return;
    }
}

/// Connects and disconnets on success. Usefull for the test runner so that we block the main thread until we are ready.
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

    stream.close();
}
