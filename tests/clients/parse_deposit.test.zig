const parse = @import("zabi").clients.op_parse;
const serialize = @import("zabi").clients.op_serialize;
const std = @import("std");
const testing = std.testing;
const transaction = @import("zabi").types.transactions;
const utils = @import("zabi").utils.utils;

const DepositTransaction = transaction.DepositTransaction;

const parseDepositTransaction = parse.parseDepositTransaction;
const serializeDepositTransaction = serialize.serializeDepositTransaction;

test "Base" {
    const tx: DepositTransaction = .{
        .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
        .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        .data = null,
        .to = null,
        .isSystemTx = false,
        .mint = 0,
        .gas = 0,
        .value = 0,
    };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "To" {
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"), .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "Data" {
    const tx: DepositTransaction = .{
        .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
        .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        .data = @constCast(&[_]u8{ 0x12, 0x34 }),
        .to = null,
        .isSystemTx = false,
        .mint = 0,
        .gas = 0,
        .value = 0,
    };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "Mint" {
    const tx: DepositTransaction = .{
        .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
        .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        .data = null,
        .to = null,
        .isSystemTx = false,
        .mint = 69,
        .gas = 0,
        .value = 0,
    };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "Gas" {
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 69, .value = 0 };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "Value" {
    const tx: DepositTransaction = .{
        .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
        .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        .data = null,
        .to = null,
        .isSystemTx = false,
        .mint = 0,
        .gas = 0,
        .value = 69,
    };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "SystemTx" {
    const tx: DepositTransaction = .{
        .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
        .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"),
        .data = null,
        .to = null,
        .isSystemTx = true,
        .mint = 0,
        .gas = 0,
        .value = 0,
    };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "Errors" {
    try testing.expectError(error.InvalidTransactionType, parseDepositTransaction(testing.allocator, @constCast(&[_]u8{ 0x03, 0x00 })));
}
