const std = @import("std");

pub const Anvil = @This();

id: i32,
alloc: std.mem.Allocator,
result: std.ChildProcess,
thread: std.Thread,

pub fn init(self: *Anvil, alloc: std.mem.Allocator) !void {
    self.alloc = alloc;
    self.thread = try std.Thread.spawn(.{}, start, .{self});
}

// pub fn deinit(self: *Anvil) void {
//     _ = self.result.kill() catch |err| {
//         std.io.getStdErr().writer().writeAll(@errorName(err)) catch {};
//     };
//     self.thread.detach();
// }

pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", "https://eth-mainnet.alchemyapi.io/v2/C3JEvfW6VgtqZQa-Qp1E-2srEiIc02sD", "--fork-block-number", "19062632", "--port", "8545" }, self.alloc);
    result.stdin_behavior = .Close;
    result.stdout_behavior = .Close;
    result.stderr_behavior = .Inherit;

    try result.spawn();

    self.result = result;
    self.id = result.id;
}
