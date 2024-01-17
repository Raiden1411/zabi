const std = @import("std");
const rlp = @import("rlp.zig");
const transaction = @import("meta/transaction.zig");
const testing = std.testing;
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;

pub fn serializeTransaction(alloc: Allocator, tx: transaction.TransactionEnvelope) ![]u8 {
    return switch (tx) {
        .eip1559 => |val| try serializeTransactionEIP1559(alloc, val),
        .eip2930 => |val| try serializeTransactionEIP2930(alloc, val),
        .legacy => |val| try serializeTransactionLegacy(alloc, val),
    };
}

pub fn serializeTransactionEIP1559(alloc: Allocator, tx: transaction.TransactionEnvelopeEip1559) ![]u8 {
    if (tx.type != 2) return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(alloc, tx.accessList);
    defer alloc.free(prep_access);

    const envelope: transaction.EnvelopeEip1559 = .{ tx.chainId, tx.nonce, tx.maxPriorityFeePerGas, tx.maxFeePerGas, tx.gas, tx.to, tx.value, tx.data, prep_access };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionEIP2930(alloc: Allocator, tx: transaction.TransactionEnvelopeEip2930) ![]u8 {
    if (tx.type != 1) return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(alloc, tx.accessList);
    defer alloc.free(prep_access);

    const envelope: transaction.EnvelopeEip2930 = .{ tx.chainId, tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data, prep_access };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionLegacy(alloc: Allocator, tx: transaction.TransactionEnvelopeLegacy) ![]u8 {
    if (tx.type != 0) return error.InvalidTransactionType;

    const envelope: transaction.EnvelopeLegacy = .{ tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});

    return encoded;
}

pub fn prepareAccessList(alloc: Allocator, access_list: []const transaction.AccessList) ![]Tuple(&[_]type{ types.Hex, []const types.Hex }) {
    var tuple_list = std.ArrayList(Tuple(&[_]type{ types.Hex, []const types.Hex })).init(alloc);
    errdefer tuple_list.deinit();

    for (access_list) |access| {
        if (!try utils.isAddress(alloc, access.address)) return error.InvalidAddress;

        for (access.storageKeys) |keys| if (!utils.isHash(keys)) return error.InvalidHash;

        try tuple_list.append(.{ access.address, access.storageKeys });
    }

    return try tuple_list.toOwnedSlice();
}

test "Base eip 1559" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip 1559" {
    const zero = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} });
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02dd018080808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 1559" {
    const min = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} });
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02c90180808080808080c0", hex);
}

test "Base eip1559 with gas" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ef01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip1559 with accessList" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f88b01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip1559 with data" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f101458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip 2930" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip eip2930" {
    const zero = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} });
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01dc0180808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 2930" {
    const min = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} });
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01c801808080808080c0", hex);
}

test "Base eip2930 with gas" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ea0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip2930 with accessList" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01f8860145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip2930 with data" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ec0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip legacy" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Zero eip legacy" {
    const zero = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null });
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da80808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080", hex);
}

test "Minimal eip legacy" {
    const min = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null });
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("c6808080808080", hex);
}

test "Base legacy with gas" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e845847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Base legacy with data" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234" });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("ea45847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234", hex);
}

test "Serialize Transaction Base" {
    const base_legacy = try serializeTransaction(testing.allocator, .{ .legacy = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null } });
    defer testing.allocator.free(base_legacy);

    const hex_legacy = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_legacy)});
    defer testing.allocator.free(hex_legacy);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex_legacy);

    const base_2930 = try serializeTransaction(testing.allocator, .{ .eip2930 = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} } });
    defer testing.allocator.free(base_2930);

    const hex_2930 = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_2930)});
    defer testing.allocator.free(hex_2930);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex_2930);

    const base = try serializeTransaction(testing.allocator, .{ .eip1559 = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} } });
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}
