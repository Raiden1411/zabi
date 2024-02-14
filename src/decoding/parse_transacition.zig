const signer = @import("secp256k1");
const std = @import("std");
const rlp = @import("../encoding/rlp.zig");
const serialize = @import("../encoding/serialize.zig");
const testing = std.testing;
const transaction = @import("../meta/transaction.zig");
const utils = @import("../utils.zig");

// Types
const AccessList = transaction.AccessList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const EncodedAccessList = transaction.EncodedAccessList;
const EnvelopeEip1559 = transaction.EnvelopeEip1559;
const EnvelopeEip2930 = transaction.EnvelopeEip2930;
const EnvelopeLegacy = transaction.EnvelopeLegacy;
const EnvelopeEip1559Signed = transaction.EnvelopeEip1559Signed;
const EnvelopeEip2930Signed = transaction.EnvelopeEip2930Signed;
const EnvelopeLegacySigned = transaction.EnvelopeLegacySigned;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionEnvelopeEip1559 = transaction.TransactionEnvelopeEip1559;
const TransactionEnvelopeEip2930 = transaction.TransactionEnvelopeEip2930;
const TransactionEnvelopeLegacy = transaction.TransactionEnvelopeLegacy;
const TransactionEnvelopeSigned = transaction.TransactionEnvelopeSigned;
const TransactionEnvelopeEip1559Signed = transaction.TransactionEnvelopeEip1559Signed;
const TransactionEnvelopeEip2930Signed = transaction.TransactionEnvelopeEip2930Signed;
const TransactionEnvelopeLegacySigned = transaction.TransactionEnvelopeLegacySigned;

pub fn ParsedTransaction(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

/// Parses unsigned serialized transactions. Creates and arena to manage memory.
/// Caller needs to call deinit to free memory.
pub fn parseTransaction(alloc: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelope) {
    var parsed: ParsedTransaction(TransactionEnvelope) = .{ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer parsed.arena.deinit();

    const allocator = parsed.arena.allocator();
    parsed.value = try parseTransactionLeaky(allocator, serialized);

    return parsed;
}

/// Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseTransactionLeaky(alloc: Allocator, serialized: []const u8) !TransactionEnvelope {
    const hexed = if (std.mem.startsWith(u8, serialized, "0x")) serialized[2..] else serialized;

    var bytes = hexed;

    if (utils.isHexString(serialized)) {
        var buffer: [1024]u8 = undefined;
        // If we failed to convert from hex we assume that serialized are already in bytes.
        const decoded = try std.fmt.hexToBytes(buffer[0..], hexed);
        bytes = decoded;
    }

    if (bytes[0] == 2)
        return .{ .eip1559 = try parseEip1559Transaction(alloc, bytes) };
    if (bytes[0] == 1)
        return .{ .eip2930 = try parseEip2930Transaction(alloc, bytes) };
    if (bytes[0] >= 0xc0)
        return .{ .legacy = try parseLegacyTransaction(alloc, bytes) };

    return error.InvalidTransactionType;
}

/// Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip1559Transaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeEip1559 {
    if (serialized[0] != 2)
        return error.InvaliTransactionType;

    const chainId, const nonce, const max_priority, const max_fee, const gas, const address, const value, const data, const access_list = try rlp.decodeRlp(alloc, EnvelopeEip1559, serialized[1..]);
    const list = try parseAccessList(alloc, access_list);
    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    return .{ .chainId = chainId, .nonce = nonce, .maxPriorityFeePerGas = max_priority, .maxFeePerGas = max_fee, .gas = gas, .to = addr, .value = value, .data = data_hex, .accessList = list };
}

/// Parses unsigned serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip2930Transaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeEip2930 {
    if (serialized[0] != 1)
        return error.InvaliTransactionType;

    const chainId, const nonce, const gas_price, const gas, const address, const value, const data, const access_list = try rlp.decodeRlp(alloc, EnvelopeEip2930, serialized[1..]);
    const list = try parseAccessList(alloc, access_list);
    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    return .{ .chainId = chainId, .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex, .accessList = list };
}

/// Parses unsigned serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseLegacyTransaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeLegacy {
    const nonce, const gas_price, const gas, const address, const value, const data = try rlp.decodeRlp(alloc, EnvelopeLegacy, serialized);
    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    return .{ .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex };
}

/// Parses signed serialized transactions. Creates and arena to manage memory.
/// Caller needs to call deinit to free memory.
pub fn parseSignedTransaction(alloc: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelopeSigned) {
    var parsed: ParsedTransaction(TransactionEnvelopeSigned) = .{ .arena = try alloc.create(ArenaAllocator), .value = undefined };
    errdefer alloc.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(alloc);
    errdefer parsed.arena.deinit();

    const allocator = parsed.arena.allocator();
    parsed.value = try parseSignedTransactionLeaky(allocator, serialized);

    return parsed;
}

/// Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedTransactionLeaky(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeSigned {
    const hexed = if (std.mem.startsWith(u8, serialized, "0x")) serialized[2..] else serialized;

    var bytes = hexed;

    if (utils.isHexString(serialized)) {
        var buffer: [1024]u8 = undefined;
        // If we failed to convert from hex we assume that serialized are already in bytes.
        const decoded = std.fmt.hexToBytes(buffer[0..], hexed) catch hexed;
        bytes = decoded;
    }

    if (bytes[0] == 2)
        return .{ .eip1559 = try parseSignedEip1559Transaction(alloc, bytes) };
    if (bytes[0] == 1)
        return .{ .eip2930 = try parseSignedEip2930Transaction(alloc, bytes) };
    if (bytes[0] >= 0xc0)
        return .{ .legacy = try parseSignedLegacyTransaction(alloc, bytes) };

    return error.InvalidTransactionType;
}

/// Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip1559Transaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeEip1559Signed {
    if (serialized[0] != 2)
        return error.InvaliTransactionType;

    const chainId, const nonce, const max_priority, const max_fee, const gas, const address, const value, const data, const access_list, const v, const r, const s = try rlp.decodeRlp(alloc, EnvelopeEip1559Signed, serialized[1..]);
    const list = try parseAccessList(alloc, access_list);

    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    const rr = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(r)});
    const ss = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(s)});

    return .{ .chainId = chainId, .nonce = nonce, .maxPriorityFeePerGas = max_priority, .maxFeePerGas = max_fee, .gas = gas, .to = addr, .value = value, .data = data_hex, .accessList = list, .r = rr, .s = ss, .v = v };
}

/// Parses signed serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip2930Transaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeEip2930Signed {
    if (serialized[0] != 1)
        return error.InvaliTransactionType;

    const chainId, const nonce, const gas_price, const gas, const address, const value, const data, const access_list, const v, const r, const s = try rlp.decodeRlp(alloc, EnvelopeEip2930Signed, serialized[1..]);
    const list = try parseAccessList(alloc, access_list);

    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    const rr = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(r)});
    const ss = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(s)});

    return .{ .chainId = chainId, .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex, .accessList = list, .r = rr, .s = ss, .v = v };
}

/// Parses signed serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedLegacyTransaction(alloc: Allocator, serialized: []const u8) !TransactionEnvelopeLegacySigned {
    const nonce, const gas_price, const gas, const address, const value, const data, const v, const r, const s = try rlp.decodeRlp(alloc, EnvelopeLegacySigned, serialized);

    const addr = if (address) |addy| try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(addy)})) else null;
    const data_hex = if (data) |d| try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(d)}) else null;

    const rr = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(r)});
    const ss = try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(s)});

    const chainId = if (v > 0 and r.len == 0 and s.len == 0) v else 0;

    if (chainId != 0)
        return .{ .chainId = chainId, .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex, .r = rr, .s = ss, .v = v };

    if (v < 0) return error.InvalidRecoveryId;

    const recover_with_id = @divExact(v - 35, 2);

    if (recover_with_id > 0)
        return .{ .chainId = recover_with_id, .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex, .r = rr, .s = ss, .v = v };

    if (v != 27 or v != 28)
        return error.InvalidRecoveryId;

    return .{ .nonce = nonce, .gasPrice = gas_price, .gas = gas, .to = addr, .value = value, .data = data_hex, .r = rr, .s = ss, .v = v };
}

/// Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseAccessList(alloc: Allocator, access_list: []const EncodedAccessList) ![]const AccessList {
    var list = std.ArrayList(AccessList).init(alloc);
    errdefer list.deinit();

    for (access_list) |item| {
        const address, const storage_keys = item;
        var access: AccessList = .{ .address = try utils.toChecksum(alloc, try std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(address)})), .storageKeys = undefined };

        var keys = std.ArrayList([]const u8).init(alloc);
        errdefer keys.deinit();

        for (storage_keys) |key| {
            try keys.append(try std.fmt.allocPrint(alloc, "0x{s}", .{std.fmt.fmtSliceHexLower(key)}));
        }
        access.storageKeys = try keys.toOwnedSlice();

        try list.append(access);
    }

    return try list.toOwnedSlice();
}

test "Base eip 1559" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Zero eip 1559" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} };
    const zero = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Minimal eip 1559" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} };
    const min = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Base eip1559 with gas" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Base eip1559 with accessList" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} };
    const base = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Base eip1559 with data" {
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP1559(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip1559);
}

test "Base eip 2930" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Zero eip eip2930" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} };
    const zero = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Minimal eip 2930" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} };
    const min = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Base eip2930 with gas" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Base eip2930 with accessList" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} };
    const base = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Base eip2930 with data" {
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} };
    const base = try serialize.serializeTransactionEIP2930(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.eip2930);
}

test "Base eip legacy" {
    const tx: TransactionEnvelopeLegacy = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null };
    const base = try serialize.serializeTransactionLegacy(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Zero eip legacy" {
    const tx: TransactionEnvelopeLegacy = .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null };
    const zero = try serialize.serializeTransactionLegacy(testing.allocator, tx, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Minimal eip legacy" {
    const tx: TransactionEnvelopeLegacy = .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null };
    const min = try serialize.serializeTransactionLegacy(testing.allocator, tx, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Base legacy with gas" {
    const tx: TransactionEnvelopeLegacy = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null };
    const base = try serialize.serializeTransactionLegacy(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Base legacy with data" {
    const tx: TransactionEnvelopeLegacy = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234" };
    const base = try serialize.serializeTransactionLegacy(testing.allocator, tx, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Serialize eip1559 with signature" {
    const sig = try generateSignature("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");
    const tx: TransactionEnvelopeEip1559 = .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" };

    const encoded = try serialize.serializeTransactionEIP1559(testing.allocator, tx, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: TransactionEnvelopeEip1559Signed = .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", .v = 1, .r = "0xd4d68c02302962fa53289fda5616c9e19a9d63b3956d63d177097143b2093e3e", .s = "0x25e1dd76721b4fc48eb5e2f91bf9132699036deccd45b3fa9d77b1d9b7628fb2" };

    try testing.expectEqualDeep(tx_signed, parsed.value.eip1559);
}

test "Serialize eip2930 with signature" {
    const sig = try generateSignature("01ec827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");
    const tx: TransactionEnvelopeEip2930 = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" };

    const encoded = try serialize.serializeTransactionEIP2930(testing.allocator, tx, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: TransactionEnvelopeEip2930Signed = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", .v = 1, .r = "0x855b7b9d7f752dd108609930a5dd9ced9c131936d84d5c302a6a4edd0c50101a", .s = "0x75fc0c4af1cf18d5bf15a9960b1988d2fbf9ae6351a957dd572e95adbbf8c26f" };

    try testing.expectEqualDeep(tx_signed, parsed.value.eip2930);
}

test "Serialize legacy with signature" {
    const sig = try generateSignature("ed8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080827a698080");
    const tx: TransactionEnvelopeLegacy = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" };

    const encoded = try serialize.serializeTransactionLegacy(testing.allocator, tx, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: TransactionEnvelopeLegacySigned = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", .v = 62709, .r = "0xa918ad4845f590df2667eceacdb621dcedf9c3efefd7f783d5f45840131c338d", .s = "0x59a2e246acdab8cfdc51b764ec20e4a59ca1998d8a101dba01cd1cb34c1179a0" };

    try testing.expectEqualDeep(tx_signed, parsed.value.legacy);
}

fn generateSignature(message: []const u8) !signer.Signature {
    const wallet = try signer.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
    const buffer = try testing.allocator.alloc(u8, message.len / 2);
    defer testing.allocator.free(buffer);

    _ = try std.fmt.hexToBytes(buffer, message);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(buffer, &hash, .{});
    return try wallet.sign(hash);
}
