const std = @import("std");

pub const Anvil = struct {
    id: i32,
    result: std.ChildProcess,

    pub fn init(alloc: std.mem.Allocator) !Anvil {
        var result = std.ChildProcess.init(&.{ "anvil", "-f", "https://ethereum.publicnode.com", "--fork-block-number", "19062632" }, alloc);
        try result.spawn();

        return .{ .result = result, .id = result.id };
    }

    pub fn deinit(self: *Anvil) !std.ChildProcess.Term {
        return try self.result.kill();
    }
};
