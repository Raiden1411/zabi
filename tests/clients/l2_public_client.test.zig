const client = @import("zabi").clients;
const std = @import("std");
const test_clients = @import("../constants.zig");
const testing = std.testing;
const utils = @import("zabi").utils.utils;

const Anvil = @import("zabi").clients.Anvil;
const HttpProvider = client.Provider.HttpProvider;

test "GetWithdrawMessages" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    const op_sepolia = try std.process.getEnvVarOwned(testing.allocator, "ANVIL_FORK_URL_OP_SEPOLIA");
    defer testing.allocator.free(op_sepolia);

    var anvil: Anvil = undefined;
    defer anvil.deinit();

    anvil.initClient(.{ .allocator = testing.allocator, .io = threaded_io.io() });

    try anvil.reset(.{ .forking = .{ .jsonRpcUrl = op_sepolia } });

    if (true) return error.SkipZigTest;
    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const messages = try op.provider.getWithdrawMessagesL2(testing.allocator, try utils.hashToBytes("0x078be3962b143952b4fd8567640b14c3682b8a941000c7d92394faf0e40cb1e8"));
    defer testing.allocator.free(messages.messages);

    const receipt = try op.provider.getTransactionReceipt(try utils.hashToBytes("0x078be3962b143952b4fd8567640b14c3682b8a941000c7d92394faf0e40cb1e8"));
    defer receipt.deinit();

    try testing.expect(messages.messages.len != 0);
    try testing.expect(messages.blockNumber == receipt.response.legacy.blockNumber.?);
}

test "GetBaseFee" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.provider.getBaseL1Fee();

    try testing.expect(fee != 0);
}

test "EstimateL1Gas" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.provider.estimateL1Gas(testing.allocator, .{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .gas = 21000,
        .maxFeePerGas = try utils.parseGwei(10),
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .chainId = 11155420,
        .value = try utils.parseGwei(1),
        .accessList = &.{},
        .nonce = 69,
    });

    try testing.expect(fee != 0);
}

test "EstimateL1GasFee" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.provider.estimateL1GasFee(testing.allocator, .{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .gas = 21000,
        .maxFeePerGas = try utils.parseGwei(10),
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .chainId = 11155420,
        .value = try utils.parseGwei(1),
        .accessList = &.{},
        .nonce = 69,
    });

    try testing.expect(fee != 0);
}

test "EstimateTotalGas" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.provider.estimateTotalGas(testing.allocator, .{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .gas = 21000,
        .maxFeePerGas = try utils.parseGwei(10),
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .chainId = 11155420,
        .value = try utils.parseGwei(1),
        .accessList = &.{},
        .nonce = 69,
    });

    try testing.expect(fee != 0);
}

test "EstimateTotalFees" {
    var threaded_io: std.Io.Threaded = .init(testing.allocator);
    defer threaded_io.deinit();

    var op = try HttpProvider.init(.{
        .allocator = testing.allocator,
        .io = threaded_io.io(),
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.provider.estimateL1Gas(testing.allocator, .{
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .gas = 21000,
        .maxFeePerGas = try utils.parseGwei(10),
        .maxPriorityFeePerGas = try utils.parseGwei(2),
        .chainId = 11155420,
        .value = try utils.parseGwei(1),
        .accessList = &.{},
        .nonce = 69,
    });

    try testing.expect(fee != 0);
}
