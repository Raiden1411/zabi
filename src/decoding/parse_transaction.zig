const meta = @import("../meta/utils.zig");
const std = @import("std");
const rlp = @import("../decoding/rlp_decode.zig");
const serialize = @import("../encoding/serialize.zig");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const utils = @import("../utils/utils.zig");

// Types
const AccessList = transaction.AccessList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const BerlinEnvelope = transaction.BerlinEnvelope;
const BerlinEnvelopeSigned = transaction.BerlinEnvelopeSigned;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const BerlinTransactionEnvelopeSigned = transaction.BerlinTransactionEnvelopeSigned;
const CancunEnvelope = transaction.CancunEnvelope;
const CancunEnvelopeSigned = transaction.CancunEnvelopeSigned;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const CancunTransactionEnvelopeSigned = transaction.CancunTransactionEnvelopeSigned;
const LegacyEnvelope = transaction.LegacyEnvelope;
const LegacyEnvelopeSigned = transaction.LegacyEnvelopeSigned;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LegacyTransactionEnvelopeSigned = transaction.LegacyTransactionEnvelopeSigned;
const LondonEnvelope = transaction.LondonEnvelope;
const LondonEnvelopeSigned = transaction.LondonEnvelopeSigned;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const LondonTransactionEnvelopeSigned = transaction.LondonTransactionEnvelopeSigned;
const Signature = @import("../crypto/signature.zig").Signature;
const Signer = @import("../crypto/Signer.zig");
const StructToTupleType = meta.StructToTupleType;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionEnvelopeSigned = transaction.TransactionEnvelopeSigned;

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
pub fn parseTransaction(allocator: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelope) {
    var parsed: ParsedTransaction(TransactionEnvelope) = .{ .arena = try allocator.create(ArenaAllocator), .value = undefined };
    errdefer allocator.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    const arena_allocator = parsed.arena.allocator();
    parsed.value = try parseTransactionLeaky(arena_allocator, serialized);

    return parsed;
}

/// Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseTransactionLeaky(allocator: Allocator, serialized: []const u8) !TransactionEnvelope {
    const hexed = if (std.mem.startsWith(u8, serialized, "0x")) serialized[2..] else serialized;

    var bytes = hexed;

    if (utils.isHexString(serialized)) {
        var buffer: [1024]u8 = undefined;
        // If we failed to convert from hex we assume that serialized are already in bytes.
        const decoded = try std.fmt.hexToBytes(buffer[0..], hexed);
        bytes = decoded;
    }

    if (bytes[0] == 3)
        return .{ .cancun = try parseEip4844Transaction(allocator, bytes) };
    if (bytes[0] == 2)
        return .{ .london = try parseEip1559Transaction(allocator, bytes) };
    if (bytes[0] == 1)
        return .{ .berlin = try parseEip2930Transaction(allocator, bytes) };
    if (bytes[0] >= 0xc0)
        return .{ .legacy = try parseLegacyTransaction(allocator, bytes) };

    return error.InvalidTransactionType;
}
/// Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip4844Transaction(allocator: Allocator, serialized: []const u8) !CancunTransactionEnvelope {
    if (serialized[0] != 3)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce,
    const max_priority,
    const max_fee, 
    const gas, 
    const address, 
    const value, 
    const data, 
    const access_list,
    const max_blob_gas,
    const blob_hashes = try rlp.decodeRlp(allocator, CancunEnvelope, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .maxPriorityFeePerGas = max_priority,
        .maxFeePerGas = max_fee,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
        .maxFeePerBlobGas = max_blob_gas,
        .blobVersionedHashes = blob_hashes,
    };
}
/// Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip1559Transaction(allocator: Allocator, serialized: []const u8) !LondonTransactionEnvelope {
    if (serialized[0] != 2)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce,
    const max_priority,
    const max_fee, 
    const gas, 
    const address, 
    const value, 
    const data, 
    const access_list = try rlp.decodeRlp(allocator, LondonEnvelope, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .maxPriorityFeePerGas = max_priority,
        .maxFeePerGas = max_fee,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
    };
}

/// Parses unsigned serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip2930Transaction(allocator: Allocator, serialized: []const u8) !BerlinTransactionEnvelope {
    if (serialized[0] != 1)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce, 
    const gas_price, 
    const gas,
    const address,
    const value,
    const data, 
    const access_list = try rlp.decodeRlp(allocator, BerlinEnvelope, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .gasPrice = gas_price,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
    };
}

/// Parses unsigned serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseLegacyTransaction(allocator: Allocator, serialized: []const u8) !LegacyTransactionEnvelope {
    // zig fmt: off
    const nonce, 
    const gas_price, 
    const gas,
    const address,
    const value,
    const data = try rlp.decodeRlp(allocator, LegacyEnvelope, serialized);
    // zig fmt: on

    return .{
        .nonce = nonce,
        .gasPrice = gas_price,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
    };
}

/// Parses signed serialized transactions. Creates and arena to manage memory.
/// Caller needs to call deinit to free memory.
pub fn parseSignedTransaction(allocator: Allocator, serialized: []const u8) !ParsedTransaction(TransactionEnvelopeSigned) {
    var parsed: ParsedTransaction(TransactionEnvelopeSigned) = .{ .arena = try allocator.create(ArenaAllocator), .value = undefined };
    errdefer allocator.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    const arena_allocator = parsed.arena.allocator();
    parsed.value = try parseSignedTransactionLeaky(arena_allocator, serialized);

    return parsed;
}

/// Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedTransactionLeaky(allocator: Allocator, serialized: []const u8) !TransactionEnvelopeSigned {
    const hexed = if (std.mem.startsWith(u8, serialized, "0x")) serialized[2..] else serialized;

    var bytes = hexed;

    if (utils.isHexString(serialized)) {
        var buffer: [1024]u8 = undefined;
        // If we failed to convert from hex we assume that serialized are already in bytes.
        const decoded = std.fmt.hexToBytes(buffer[0..], hexed) catch hexed;
        bytes = decoded;
    }

    if (bytes[0] == 3)
        return .{ .cancun = try parseSignedEip4844Transaction(allocator, bytes) };
    if (bytes[0] == 2)
        return .{ .london = try parseSignedEip1559Transaction(allocator, bytes) };
    if (bytes[0] == 1)
        return .{ .berlin = try parseSignedEip2930Transaction(allocator, bytes) };
    if (bytes[0] >= 0xc0)
        return .{ .legacy = try parseSignedLegacyTransaction(allocator, bytes) };

    return error.InvalidTransactionType;
}
/// Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip4844Transaction(allocator: Allocator, serialized: []const u8) !CancunTransactionEnvelopeSigned {
    if (serialized[0] != 3)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce,
    const max_priority,
    const max_fee, 
    const gas, 
    const address, 
    const value, 
    const data, 
    const access_list,
    const max_blob_gas,
    const blob_hashes,
    const v,
    const r,
    const s = try rlp.decodeRlp(allocator, CancunEnvelopeSigned, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .maxPriorityFeePerGas = max_priority,
        .maxFeePerGas = max_fee,
        .maxFeePerBlobGas = max_blob_gas,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
        .blobVersionedHashes = blob_hashes,
        .r = r,
        .s = s,
        .v = v,
    };
}
/// Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip1559Transaction(allocator: Allocator, serialized: []const u8) !LondonTransactionEnvelopeSigned {
    if (serialized[0] != 2)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce,
    const max_priority,
    const max_fee, 
    const gas, 
    const address, 
    const value, 
    const data, 
    const access_list,
    const v,
    const r,
    const s = try rlp.decodeRlp(allocator, LondonEnvelopeSigned, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .maxPriorityFeePerGas = max_priority,
        .maxFeePerGas = max_fee,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
        .r = r,
        .s = s,
        .v = v,
    };
}

/// Parses signed serialized eip2930 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip2930Transaction(allocator: Allocator, serialized: []const u8) !BerlinTransactionEnvelopeSigned {
    if (serialized[0] != 1)
        return error.InvalidTransactionType;

    // zig fmt: off
    const chainId, 
    const nonce,
    const gas_price,
    const gas, 
    const address, 
    const value, 
    const data, 
    const access_list,
    const v,
    const r,
    const s = try rlp.decodeRlp(allocator, BerlinEnvelopeSigned, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);

    return .{
        .chainId = chainId,
        .nonce = nonce,
        .gasPrice = gas_price,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .accessList = list,
        .r = r,
        .s = s,
        .v = v,
    };
}

/// Parses signed serialized legacy transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedLegacyTransaction(allocator: Allocator, serialized: []const u8) !LegacyTransactionEnvelopeSigned {
    // zig fmt: off
    const nonce, 
    const gas_price, 
    const gas,
    const address,
    const value,
    const data,
    const v,
    const r,
    const s = try rlp.decodeRlp(allocator, LegacyEnvelopeSigned, serialized);
    // zig fmt: on

    const chainId = if (v > 0 and r == null and s == null) v else 0;

    if (chainId != 0)
        return .{
            .chainId = chainId,
            .nonce = nonce,
            .gasPrice = gas_price,
            .gas = gas,
            .to = address,
            .value = value,
            .data = data,
            .r = r,
            .s = s,
            .v = v,
        };

    if (v < 0) return error.InvalidRecoveryId;

    const recover_with_id = @divExact(v - 35, 2);

    if (recover_with_id > 0)
        return .{
            .chainId = recover_with_id,
            .nonce = nonce,
            .gasPrice = gas_price,
            .gas = gas,
            .to = address,
            .value = value,
            .data = data,
            .r = r,
            .s = s,
            .v = v,
        };

    if (v != 27 or v != 28)
        return error.InvalidRecoveryId;

    return .{
        .nonce = nonce,
        .gasPrice = gas_price,
        .gas = gas,
        .to = address,
        .value = value,
        .data = data,
        .r = r,
        .s = s,
        .v = v,
    };
}

/// Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseAccessList(allocator: Allocator, access_list: []const StructToTupleType(AccessList)) ![]const AccessList {
    var list = std.ArrayList(AccessList).init(allocator);
    errdefer list.deinit();

    for (access_list) |item| {
        const address, const storage_keys = item;

        try list.ensureUnusedCapacity(1);
        list.appendAssumeCapacity(.{ .address = address, .storageKeys = storage_keys });
    }

    return try list.toOwnedSlice();
}

test "Base eip 4844" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: CancunTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{}, .maxFeePerBlobGas = 0, .blobVersionedHashes = &.{[_]u8{0} ** 32} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .cancun = tx }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.cancun);
}

test "Base eip 1559" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Zero eip 1559" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = to, .value = 0, .data = null, .accessList = &.{} };
    const zero = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Minimal eip 1559" {
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} };
    const min = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Base eip1559 with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Base eip1559 with accessList" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = [_]u8{0} ** 20, .storageKeys = &.{ [_]u8{0} ** 31 ++ [1]u8{1}, [_]u8{0} ** 31 ++ [1]u8{2} } }} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Base eip1559 with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LondonTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = @constCast(&[_]u8{ 0x12, 0x34 }), .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.london);
}

test "Base eip 2930" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Zero eip eip2930" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = to, .value = 0, .data = null, .accessList = &.{} };
    const zero = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Minimal eip 2930" {
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} };
    const min = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Base eip2930 with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Base eip2930 with accessList" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = [_]u8{0} ** 20, .storageKeys = &.{ [_]u8{0} ** 31 ++ [1]u8{1}, [_]u8{0} ** 31 ++ [1]u8{2} } }} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Base eip2930 with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = @constCast(&[_]u8{ 0x12, 0x34 }), .accessList = &.{} };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.berlin);
}

test "Base eip legacy" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LegacyTransactionEnvelope = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = to, .value = try utils.parseEth(1), .data = null };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Zero eip legacy" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LegacyTransactionEnvelope = .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = to, .value = 0, .data = null };
    const zero = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, null);
    defer testing.allocator.free(zero);

    const parsed = try parseTransaction(testing.allocator, zero);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Minimal eip legacy" {
    const tx: LegacyTransactionEnvelope = .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null };
    const min = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, null);
    defer testing.allocator.free(min);

    const parsed = try parseTransaction(testing.allocator, min);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Base legacy with gas" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LegacyTransactionEnvelope = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = null };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Base legacy with data" {
    const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const tx: LegacyTransactionEnvelope = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = to, .value = try utils.parseEth(1), .data = @constCast(&[_]u8{ 0x12, 0x34 }) };
    const base = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, null);
    defer testing.allocator.free(base);

    const parsed = try parseTransaction(testing.allocator, base);
    defer parsed.deinit();

    try testing.expectEqualDeep(tx, parsed.value.legacy);
}

test "Serialize eip4844 with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");

    const tx: CancunTransactionEnvelope = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = to, .value = try utils.parseEth(1), .data = null, .accessList = &.{}, .maxFeePerBlobGas = 0, .blobVersionedHashes = &.{[_]u8{0} ** 32} };

    const sig = try generateSignature("03f8500145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c080e1a00000000000000000000000000000000000000000000000000000000000000000");

    const encoded = try serialize.serializeTransaction(testing.allocator, .{ .cancun = tx }, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: CancunTransactionEnvelopeSigned = .{ .chainId = 1, .nonce = 69, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 0, .value = try utils.parseEth(1), .accessList = &.{}, .to = to, .maxFeePerBlobGas = 0, .blobVersionedHashes = &.{[_]u8{0} ** 32}, .v = 0, .r = sig.r, .s = sig.s };

    try testing.expectEqualDeep(tx_signed, parsed.value.cancun);
}
test "Serialize eip1559 with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");
    const tx: LondonTransactionEnvelope = .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = to };

    const encoded = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: LondonTransactionEnvelopeSigned = .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = to, .v = 1, .r = sig.r, .s = sig.s };

    try testing.expectEqualDeep(tx_signed, parsed.value.london);
}

test "Serialize eip2930 with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("01ec827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");
    const tx: BerlinTransactionEnvelope = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = to };

    const encoded = try serialize.serializeTransaction(testing.allocator, .{ .berlin = tx }, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: BerlinTransactionEnvelopeSigned = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = to, .v = 1, .r = sig.r, .s = sig.s };

    try testing.expectEqualDeep(tx_signed, parsed.value.berlin);
}

test "Serialize legacy with signature" {
    const to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    const sig = try generateSignature("ed8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080827a698080");
    const tx: LegacyTransactionEnvelope = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .to = to };

    const encoded = try serialize.serializeTransaction(testing.allocator, .{ .legacy = tx }, sig);
    defer testing.allocator.free(encoded);

    const parsed = try parseSignedTransaction(testing.allocator, encoded);
    defer parsed.deinit();

    const tx_signed: LegacyTransactionEnvelopeSigned = .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .to = to, .v = 62709, .r = sig.r, .s = sig.s };

    try testing.expectEqualDeep(tx_signed, parsed.value.legacy);
}

test "Errors" {
    try testing.expectError(error.InvalidTransactionType, parseSignedEip1559Transaction(testing.allocator, &[_]u8{0x03}));
    try testing.expectError(error.InvalidTransactionType, parseSignedEip2930Transaction(testing.allocator, &[_]u8{0x03}));
    try testing.expectError(error.InvalidTransactionType, parseSignedEip4844Transaction(testing.allocator, &[_]u8{0x02}));
    try testing.expectError(error.InvalidTransactionType, parseEip4844Transaction(testing.allocator, &[_]u8{0x02}));
    try testing.expectError(error.InvalidTransactionType, parseEip1559Transaction(testing.allocator, &[_]u8{0x03}));
    try testing.expectError(error.InvalidTransactionType, parseEip2930Transaction(testing.allocator, &[_]u8{0x02}));
    try testing.expectError(error.InvalidTransactionType, parseTransaction(testing.allocator, &[_]u8{0x04}));
    try testing.expectError(error.InvalidTransactionType, parseSignedTransaction(testing.allocator, &[_]u8{0x04}));
}

fn generateSignature(message: []const u8) !Signature {
    var buffer_hex: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(buffer_hex[0..], "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
    const wallet = try Signer.init(buffer_hex);
    const buffer = try testing.allocator.alloc(u8, message.len / 2);
    defer testing.allocator.free(buffer);

    _ = try std.fmt.hexToBytes(buffer, message);

    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(buffer, &hash, .{});
    return try wallet.sign(hash);
}
