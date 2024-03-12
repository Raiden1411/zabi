const meta = @import("../../meta/utils.zig");
const rlp = @import("../../encoding/rlp.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("types/transaction.zig");
const utils = @import("../../utils/utils.zig");

const Allocator = std.mem.Allocator;
const DepositTransaction = transaction.DepositTransaction;
const StructToTupleType = meta.StructToTupleType;

/// Serializes an OP deposit transaction
/// Caller owns the memory
pub fn serializeDepositTransaction(allocator: Allocator, tx: DepositTransaction) ![]u8 {
    const data: ?[]u8 = data: {
        if (tx.data) |hex_data| {
            const slice = if (std.mem.startsWith(u8, hex_data, "0x")) hex_data[2..] else return error.ExpectedHexString;

            const buffer = try allocator.alloc(u8, if (@mod(slice.len, 2) == 0) @divExact(slice.len, 2) else slice.len);

            _ = try std.fmt.hexToBytes(buffer, slice);

            break :data buffer;
        } else break :data null;
    };
    defer if (data) |val| allocator.free(val);

    // zig fmt: off
    const envelope: StructToTupleType(DepositTransaction) = .{
        tx.sourceHash,
        tx.from,
        tx.to,
        tx.mint,
        tx.value,
        tx.gas,
        tx.isSystemTx,
        data
    };
    // zig fmt: on

    const encoded_sig = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded_sig);

    var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
    // Add the transaction type;
    serialized[0] = 0x7e;
    @memcpy(serialized[1..], encoded_sig);

    return serialized;
}

test "Base" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ca07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb92266808080808080", hex);
}

test "With From" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"), .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef850a07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb922669470997970c51812dc3a010c7d01b50e0d17dc79c88080808080", hex);
}

test "With Data" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = "0x1234", .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ea07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb922668080808080821234", hex);
}

test "With Value" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 69 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ca07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb92266808045808080", hex);
}

test "With mint" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 69, .gas = 0, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ca07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb92266804580808080", hex);
}

test "With SystemTx" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = true, .mint = 0, .gas = 0, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ca07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb92266808080800180", hex);
}

test "With gas" {
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = null, .to = null, .isSystemTx = false, .mint = 0, .gas = 69, .value = 0 });
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("7ef83ca07f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef894f39fd6e51aad88f6f4ce6ab8827279cfffb92266808080458080", hex);
}
