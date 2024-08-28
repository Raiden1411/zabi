const client = @import("L1PubClient.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../../utils/utils.zig");
const test_clients = @import("../../../tests/constants.zig");

const L1Client = client.L1Client;

test "GetL2HashFromL1DepositInfo" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_mainnet,
    });
    defer op.deinit();

    const messages = try op.getL2HashesForDepositTransaction(try utils.hashToBytes("0x33faeeee9c6d5e19edcdfc003f329c6652f05502ffbf3218d9093b92589a42c4"));
    defer testing.allocator.free(messages);

    try testing.expectEqualSlices(u8, &try utils.hashToBytes("0xed88afbd3f126180bd5488c2212cd033c51a6f9b1765249bdb738dcac1d0cb41"), &messages[0]);
}

test "GetL2Output" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_mainnet,
    });
    defer op.deinit();

    const l2_output = try op.getL2Output(2725977);

    try testing.expectEqual(l2_output.timestamp, 1686075935);
    try testing.expectEqual(l2_output.outputIndex, 0);
    try testing.expectEqual(l2_output.l2BlockNumber, 105236863);
}

test "getSecondsToFinalize" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{ .portalAddress = try utils.addressToBytes("0x49048044D57e1C92A77f79988d21Fa8fAF74E97e") },
        },
    });
    defer op.deinit();

    const seconds = try op.getSecondsToFinalize(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
    try testing.expectEqual(seconds, 0);
}

test "GetSecondsToNextL2Output" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{},
        },
    });
    defer op.deinit();

    const block = try op.getLatestProposedL2BlockNumber();
    const seconds = try op.getSecondsToNextL2Output(block);
    try testing.expectEqual(seconds, 3600);
}

test "GetTransactionDepositEvents" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_mainnet,
    });
    defer op.deinit();

    const deposit_events = try op.getTransactionDepositEvents(try utils.hashToBytes("0xe94031c3174788c3fee7216465c50bb2b72e7a1963f5af807b3768da10827f5c"));
    defer {
        for (deposit_events) |event| testing.allocator.free(event.opaqueData);
        testing.allocator.free(deposit_events);
    }

    try testing.expect(deposit_events.len != 0);
    try testing.expectEqual(deposit_events[0].to, try utils.addressToBytes("0xbc3ed6B537f2980e66f396Fe14210A56ba3f72C4"));
}

test "GetProvenWithdrawals" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{ .portalAddress = try utils.addressToBytes("0x49048044D57e1C92A77f79988d21Fa8fAF74E97e") },
        },
    });
    defer op.deinit();

    const proven = try op.getProvenWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));

    try testing.expectEqual(proven.l2OutputIndex, 1490);
}

test "GetFinalizedWithdrawals" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{ .portalAddress = try utils.addressToBytes("0x49048044D57e1C92A77f79988d21Fa8fAF74E97e") },
        },
    });
    defer op.deinit();

    const finalized = try op.getFinalizedWithdrawals(try utils.hashToBytes("0xEC0AD491512F4EDC603C2DD7B9371A0B18D4889A23E74692101BA4C6DC9B5709"));
    try testing.expect(finalized);
}

test "Errors" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = .{
            .endpoint = .{ .uri = uri },
            .op_stack_contracts = .{},
        },
    });
    defer op.deinit();

    try testing.expectError(error.InvalidBlockNumber, op.getSecondsToNextL2Output(1));
    try testing.expectError(error.InvalidWithdrawalHash, op.getSecondsToFinalize(try utils.hashToBytes("0xe94031c3174788c3fee7216465c50bb2b72e7a1963f5af807b3768da10827f5c")));
}

test "getSecondsUntilNextGame" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_sepolia,
    });
    defer op.deinit();

    const games = try op.getGames(1, null);
    defer testing.allocator.free(games);

    const timings = try op.getSecondsUntilNextGame(1.1, @intCast(games[0].l2BlockNumber + 1));

    try testing.expect(timings.interval != 0);
}

test "Portal Version" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_sepolia,
    });
    defer op.deinit();

    const version = try op.getPortalVersion();

    try testing.expectEqual(version.major, 3);
}

test "Get Games" {
    var op = try L1Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_sepolia,
    });
    defer op.deinit();

    const games = try op.getGames(5, 69);
    testing.allocator.free(games);

    try testing.expectEqual(games.len, 5);
}
