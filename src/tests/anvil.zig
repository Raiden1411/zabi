const std = @import("std");

pub const Anvil = @This();

id: i32,
result: std.ChildProcess,

pub fn init(self: *Anvil, alloc: std.mem.Allocator) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", "https://ethereum.publicnode.com", "--fork-block-number", "19062632" }, alloc);
    try result.spawn();
    self.result = result;
    self.id = result.id;
    std.time.sleep(2 * std.time.ns_per_s);
}

pub fn deinit(self: *Anvil) void {
    std.time.sleep(2 * std.time.ns_per_s);
    _ = self.result.kill() catch {};
}
