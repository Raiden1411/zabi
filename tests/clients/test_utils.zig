const std = @import("std");
const testing = std.testing;

const Anvil = @import("zabi").clients.Anvil;

pub const ForkReset = struct {
    env_name: []const u8,
    block_number: ?u64 = null,
};

pub fn resetAnvilFork(opts: ForkReset) !void {
    var environ_map = try testing.io_instance.environ.process_environ.createMap(std.heap.page_allocator);
    defer environ_map.deinit();

    const fork_url = environ_map.get(opts.env_name) orelse return error.SkipZigTest;

    var anvil: Anvil = undefined;
    defer anvil.deinit();

    anvil.initClient(.{ .allocator = testing.allocator, .io = testing.io });

    try anvil.reset(.{ .forking = .{
        .jsonRpcUrl = fork_url,
        .blockNumber = opts.block_number,
    } });
}
