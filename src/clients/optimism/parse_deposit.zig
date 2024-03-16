const meta = @import("../../meta/utils.zig");
const rlp = @import("../../decoding/rlp_decode.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("types/transaction.zig");
const utils = @import("../../utils/utils.zig");

const serializeDepositTransaction = @import("serialize_deposit.zig").serializeDepositTransaction;

const Allocator = std.mem.Allocator;
const DepositTransaction = transaction.DepositTransaction;
const StructToTupleType = meta.StructToTupleType;

/// Parses a deposit transaction into its zig type
/// Only the data field will have allocated memory so you must free it after
pub fn parseDepositTransaction(allocator: Allocator, encoded: []u8) !DepositTransaction {
    if (encoded[0] != 0x7e)
        return error.InvalidTransactionType;

    // zig fmt: off
    const source_hash,
    const from,
    const to,
    const mint, 
    const value, 
    const gas, 
    const is_system,
    const data = try rlp.decodeRlp(allocator, StructToTupleType(DepositTransaction), encoded[1..]);
    // zig fmt: on

    const data_hex = if (data) |d| try std.fmt.allocPrint(allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    return .{ .sourceHash = source_hash, .isSystemTx = is_system, .gas = gas, .from = from, .to = to, .value = value, .data = data_hex, .mint = mint };
}

test "Base" {
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 };

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
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = "0x1234", .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);
    defer if (decoded.data) |data| testing.allocator.free(data);

    try testing.expectEqualDeep(tx, decoded);
}

test "Mint" {
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 69, .gas = 0, .value = 0 };

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
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 69 };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}

test "SystemTx" {
    const tx: DepositTransaction = .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = true, .mint = 0, .gas = 0, .value = 0 };

    const encoded = try serializeDepositTransaction(testing.allocator, tx);
    defer testing.allocator.free(encoded);

    const decoded = try parseDepositTransaction(testing.allocator, encoded);

    try testing.expectEqualDeep(tx, decoded);
}
