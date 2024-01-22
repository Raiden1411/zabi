const std = @import("std");

pub const Anvil = @This();

id: i32,
alloc: std.mem.Allocator,
result: std.ChildProcess,

pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", "https://eth-mainnet.alchemyapi.io/v2/C3JEvfW6VgtqZQa-Qp1E-2srEiIc02sD", "--fork-block-number", "19062632", "--port", "8545" }, self.alloc);
    result.stdin_behavior = .Pipe;
    result.stdout_behavior = .Pipe;
    result.stderr_behavior = .Pipe;

    try result.spawn();

    std.time.sleep(2001 * std.time.ns_per_ms);
    self.result = result;
    self.id = result.id;
}
