const std = @import("std");
const utils = @import("utils/utils.zig");

const PubClient = @import("clients/Client.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // var iter = try std.process.ArgIterator.initWithAllocator(gpa.allocator());
    // defer iter.deinit();
    //
    // _ = iter.skip();

    const uri = try std.Uri.parse("http://localhost:8545/");
    var rpc_client: PubClient = undefined;
    defer rpc_client.deinit();

    try rpc_client.init(.{
        .uri = uri,
        .allocator = gpa.allocator(),
    });

    const block_number = try rpc_client.getBlockNumber();
    defer block_number.deinit();

    var i: usize = 0;
    var rand = std.rand.DefaultPrng.init(0);

    while (i < 100) : (i += 1) {
        const num = rand.random().intRangeAtMost(u32, 0, @truncate(block_number.response));

        const block = try rpc_client.getBlockByNumber(.{ .block_number = num, .include_transaction_objects = num % 2 == 0 });
        defer block.deinit();

        const logs = try rpc_client.getLogs(.{ .fromBlock = num, .toBlock = num }, null);
        defer logs.deinit();

        const proof = try rpc_client.getProof(.{
            .address = try utils.addressToBytes("0x7F0d15C7FAae65896648C8273B6d7E43f58Fa842"),
            .storageKeys = &.{try utils.hashToBytes("0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")},
            .blockNumber = num,
        }, null);
        defer proof.deinit();

        const uncle = try rpc_client.getUncleCountByBlockNumber(.{ .block_number = num });
        defer uncle.deinit();

        if (uncle.response > 0) {
            const uncle_block = try rpc_client.getUncleByBlockNumberAndIndex(.{ .block_number = num }, 0);
            defer uncle_block.deinit();
        }
    }
}
