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

pub fn serializeTransactionEIP1559(alloc: Allocator, tx: transaction.TransactionEvelopeEip1559) ![]u8 {
    if (tx.type != 2) return error.InvalidTransactionType;

    var addr_buffer: [20]u8 = undefined;
    const addr_bytes: ?[]u8 = if (tx.to) |addr| try std.fmt.hexToBytes(addr_buffer[0..], addr[2..]) else null;

    var data_bytes: ?[]u8 = null;
    defer if (data_bytes != null) alloc.free(data_bytes.?);

    if (tx.data) |data| {
        const data_buffer = try alloc.alloc(u8, @divExact(data.len, 2));
        data_bytes = try std.fmt.hexToBytes(data_buffer, data);
    }

    const Envelope = Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const transaction.AccessList });
    const envelope: Envelope = .{ tx.chainId, tx.nonce, tx.maxPriorityFeePerGas, tx.maxFeePerGas, tx.gas, addr_bytes, tx.value, data_bytes, tx.accessList };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionEIP2930(alloc: Allocator, tx: transaction.TransactionEvelopeEip2930) ![]u8 {
    if (tx.type != 1) return error.InvalidTransactionType;

    var addr_buffer: [20]u8 = undefined;
    const addr_bytes: ?[]u8 = if (tx.to) |addr| try std.fmt.hexToBytes(addr_buffer[0..], addr[2..]) else null;

    var data_bytes: ?[]u8 = null;
    defer if (data_bytes != null) alloc.free(data_bytes.?);

    if (tx.data) |data| {
        const data_buffer = try alloc.alloc(u8, @divExact(data.len, 2));
        data_bytes = try std.fmt.hexToBytes(data_buffer, data);
    }

    const Envelope = Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const transaction.AccessList });
    const envelope: Envelope = .{ tx.chainId, tx.nonce, tx.gas, tx.gasPrice, addr_bytes, tx.value, data_bytes, tx.accessList };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}

pub fn serializeTransactionLegacy(alloc: Allocator, tx: transaction.TransactionEvelopeLegacy) ![]u8 {
    if (tx.type != 0) return error.InvalidTransactionType;

    var addr_buffer: [20]u8 = undefined;
    const addr_bytes: ?[]u8 = if (tx.to) |addr| try std.fmt.hexToBytes(addr_buffer[0..], addr[2..]) else null;

    var data_bytes: ?[]u8 = null;
    defer if (data_bytes != null) alloc.free(data_bytes.?);

    if (tx.data) |data| {
        const data_buffer = try alloc.alloc(u8, @divExact(data.len, 2));
        data_bytes = try std.fmt.hexToBytes(data_buffer, data);
    }

    const Envelope = Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex });
    const envelope: Envelope = .{ tx.nonce, tx.gasPrice, tx.gas, addr_bytes, tx.value, data_bytes };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});

    return encoded;
}

// test "FOOOO" {
//     const a = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 785, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8", .value = try utils.parseEth(1), .data = null });
//     defer testing.allocator.free(a);
//
//     std.debug.print("FOOO: {s}\n\n", .{std.fmt.fmtSliceHexLower(a)});
// }
