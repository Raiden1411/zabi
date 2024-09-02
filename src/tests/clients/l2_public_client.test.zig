const client = @import("../../clients/optimism/clients/L2PubClient.zig");
const std = @import("std");
const test_clients = @import("../constants.zig");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const L2Client = client.L2Client;

test "GetWithdrawMessages" {
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const messages = try op.getWithdrawMessages(try utils.hashToBytes("0x078be3962b143952b4fd8567640b14c3682b8a941000c7d92394faf0e40cb1e8"));
    defer testing.allocator.free(messages.messages);

    const receipt = try op.rpc_client.getTransactionReceipt(try utils.hashToBytes("0x078be3962b143952b4fd8567640b14c3682b8a941000c7d92394faf0e40cb1e8"));
    defer receipt.deinit();

    try testing.expect(messages.messages.len != 0);
    try testing.expect(messages.blockNumber == receipt.response.legacy.blockNumber.?);
}

test "GetBaseFee" {
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.getBaseL1Fee();

    try testing.expect(fee != 0);
}

test "EstimateL1Gas" {
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.estimateL1Gas(.{
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
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.estimateL1GasFee(.{
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
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.estimateTotalGas(.{
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
    var op = try L2Client(.http).init(.{
        .allocator = testing.allocator,
        .network_config = test_clients.anvil_op_sepolia,
    });
    defer op.deinit();

    const fee = try op.estimateL1Gas(.{
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

test "Ref All Decls" {
    std.testing.refAllDecls(L2Client(.http));
    std.testing.refAllDecls(L2Client(.ipc));
    std.testing.refAllDecls(L2Client(.websocket));
}
