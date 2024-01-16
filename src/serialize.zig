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

    const Envelope = Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const Tuple(&[_]type{ types.Hex, []const types.Hex }) });
    const envelope: Envelope = .{ tx.chainId, tx.nonce, tx.maxPriorityFeePerGas, tx.maxFeePerGas, tx.gas, tx.to, tx.value, tx.data, prep_access };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionEIP2930(alloc: Allocator, tx: transaction.TransactionObjectEip2930) ![]u8 {
    if (tx.type != 1) return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(alloc, tx.accessList);
    defer alloc.free(prep_access);

    const Envelope = Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const Tuple(&[_]type{ types.Hex, []const types.Hex }) });
    const envelope: Envelope = .{ tx.chainId, tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data, tx.accessList };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionLegacy(alloc: Allocator, tx: transaction.TransactionEnvelopeLegacy) ![]u8 {
    if (tx.type != 0) return error.InvalidTransactionType;

    const Envelope = Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex });
    const envelope: Envelope = .{ tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data };

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

test "FOOOO" {
    const a = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000001" } }} });
    defer testing.allocator.free(a);

    std.debug.print("FOOO: {s}\n\n", .{std.fmt.fmtSliceHexLower(a)});
}
