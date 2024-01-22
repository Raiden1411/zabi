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

pub fn deinit(self: *Anvil) void {
    std.time.sleep(2 * std.time.ns_per_s);
    self.thread.detach();
}

pub fn start(self: *Anvil) !void {
    var result = std.ChildProcess.init(&.{ "anvil", "-f", "https://ethereum.publicnode.com", "--fork-block-number", "19062632" }, self.alloc);
    result.stdin_behavior = .Pipe;
    result.stdout_behavior = .Pipe;
    result.stderr_behavior = .Pipe;

    try result.spawn();
    self.result = result;
    self.id = result.id;
    std.time.sleep(2 * std.time.ns_per_s);
}
