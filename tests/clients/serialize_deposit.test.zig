const serialize = @import("zabi-op-stack").serialize;
const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

const serializeDepositTransaction = serialize.serializeDepositTransaction;

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
    const encoded = try serializeDepositTransaction(testing.allocator, .{ .from = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), .sourceHash = try utils.hashToBytes("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8"), .data = @constCast(&[_]u8{ 0x12, 0x34 }), .to = null, .isSystemTx = false, .mint = 0, .gas = 0, .value = 0 });
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
