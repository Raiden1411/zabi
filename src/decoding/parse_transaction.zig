const meta = @import("zabi-meta").utils;
const std = @import("std");
const rlp = @import("rlp_decode.zig");
const testing = std.testing;
const transaction = @import("zabi-types").transactions;
const utils = @import("zabi-utils").utils;

// Types
const AccessList = transaction.AccessList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AuthorizationPayload = transaction.AuthorizationPayload;
const BerlinEnvelope = transaction.BerlinEnvelope;
const BerlinEnvelopeSigned = transaction.BerlinEnvelopeSigned;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const BerlinTransactionEnvelopeSigned = transaction.BerlinTransactionEnvelopeSigned;
const CancunEnvelope = transaction.CancunEnvelope;
const CancunEnvelopeSigned = transaction.CancunEnvelopeSigned;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const CancunTransactionEnvelopeSigned = transaction.CancunTransactionEnvelopeSigned;
const Eip7702Envelope = transaction.Eip7702Envelope;
const Eip7702EnvelopeSigned = transaction.Eip7702EnvelopeSigned;
const Eip7702TransactionEnvelope = transaction.Eip7702TransactionEnvelope;
const Eip7702TransactionEnvelopeSigned = transaction.Eip7702TransactionEnvelopeSigned;
const LegacyEnvelope = transaction.LegacyEnvelope;
const LegacyEnvelopeSigned = transaction.LegacyEnvelopeSigned;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LegacyTransactionEnvelopeSigned = transaction.LegacyTransactionEnvelopeSigned;
const LondonEnvelope = transaction.LondonEnvelope;
const LondonEnvelopeSigned = transaction.LondonEnvelopeSigned;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const LondonTransactionEnvelopeSigned = transaction.LondonTransactionEnvelopeSigned;
const RlpDecodeErrors = rlp.RlpDecodeErrors;
const StructToTupleType = meta.StructToTupleType;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionEnvelopeSigned = transaction.TransactionEnvelopeSigned;
const TransactionTypes = transaction.TransactionTypes;

/// Return type of `parseTransaction`.
pub fn ParsedTransaction(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        /// Cleans memory and destroys `ArenaAllocator` pointer.
        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub const ParseTransactionErrors = RlpDecodeErrors || error{ InvalidRecoveryId, InvalidTransactionType, NoSpaceLeft, InvalidLength };

/// Parses unsigned serialized transactions. Creates and arena to manage memory.\
/// This is for the cases where we need to decode access list or if the serialized transaction contains data.
///
/// **Example**
/// ```zig
/// const tx: LondonTransactionEnvelope = .{
///     .chainId = 1,
///     .nonce = 0,
///     .maxPriorityFeePerGas = 0,
///     .maxFeePerGas = 0,
///     .gas = 0,
///     .to = null,
///     .value = 0,
///     .data = null,
///     .accessList = &.{},
/// };
/// const min = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
/// defer testing.allocator.free(min);
///
/// const parsed = try parseTransaction(testing.allocator, min);
/// defer parsed.deinit();
/// ```
pub fn parseTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!ParsedTransaction(TransactionEnvelope) {
    var parsed: ParsedTransaction(TransactionEnvelope) = .{ .arena = try allocator.create(ArenaAllocator), .value = undefined };
    errdefer allocator.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    const arena_allocator = parsed.arena.allocator();
    parsed.value = try parseTransactionLeaky(arena_allocator, serialized);

    return parsed;
}

/// Parses unsigned serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
///
/// This is usefull for cases where the transaction object is expected to not have any allocated memory and it faster to decode because of it.
///
/// **Example**
/// ```zig
/// const tx: LondonTransactionEnvelope = .{
///     .chainId = 1,
///     .nonce = 0,
///     .maxPriorityFeePerGas = 0,
///     .maxFeePerGas = 0,
///     .gas = 0,
///     .to = null,
///     .value = 0,
///     .data = null,
///     .accessList = &.{},
/// };
/// const min = try serialize.serializeTransaction(testing.allocator, .{ .london = tx }, null);
/// defer testing.allocator.free(min);
///
/// const parsed = try parseTransactionLeaky(testing.allocator, min);
/// ```
pub fn parseTransactionLeaky(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!TransactionEnvelope {
    const tx_type: TransactionTypes = @enumFromInt(serialized[0]);

    switch (tx_type) {
        .eip7702 => return .{ .eip7702 = try parseEip7702Transaction(allocator, serialized) },
        .cancun => return .{ .cancun = try parseEip4844Transaction(allocator, serialized) },
        .london => return .{ .london = try parseEip1559Transaction(allocator, serialized) },
        .berlin => return .{ .berlin = try parseEip2930Transaction(allocator, serialized) },

        .deposit,
        .legacy,
        => return error.InvalidTransactionType,

        _ => return .{ .legacy = try parseLegacyTransaction(allocator, serialized) },
    }
}
/// Parses unsigned serialized eip7702 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip7702Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!Eip7702TransactionEnvelope {
    if (serialized[0] != 4)
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
    const authorization_list = try rlp.decodeRlp(Eip7702Envelope, allocator, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);
    const auth_list = try parseAuthorizationList(allocator, authorization_list);

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
        .authorizationList = auth_list,
    };
}
/// Parses unsigned serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseEip4844Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!CancunTransactionEnvelope {
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
    const blob_hashes = try rlp.decodeRlp(CancunEnvelope, allocator, serialized[1..]);
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
pub fn parseEip1559Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LondonTransactionEnvelope {
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
    const access_list = try rlp.decodeRlp(LondonEnvelope, allocator,  serialized[1..]);
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
pub fn parseEip2930Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!BerlinTransactionEnvelope {
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
    const access_list = try rlp.decodeRlp(BerlinEnvelope, allocator,  serialized[1..]);
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
pub fn parseLegacyTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LegacyTransactionEnvelope {
    if (serialized[0] < 0xc0)
        return error.InvalidTransactionType;

    // zig fmt: off
    const nonce, 
    const gas_price, 
    const gas,
    const address,
    const value,
    const data = try rlp.decodeRlp(LegacyEnvelope, allocator,  serialized);
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
pub fn parseSignedTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!ParsedTransaction(TransactionEnvelopeSigned) {
    var parsed: ParsedTransaction(TransactionEnvelopeSigned) = .{ .arena = try allocator.create(ArenaAllocator), .value = undefined };
    errdefer allocator.destroy(parsed.arena);

    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    const arena_allocator = parsed.arena.allocator();
    parsed.value = try parseSignedTransactionLeaky(arena_allocator, serialized);

    return parsed;
}

/// Parses signed serialized transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedTransactionLeaky(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!TransactionEnvelopeSigned {
    const tx_type: TransactionTypes = @enumFromInt(serialized[0]);

    switch (tx_type) {
        .eip7702 => return .{ .eip7702 = try parseSignedEip7702Transaction(allocator, serialized) },
        .cancun => return .{ .cancun = try parseSignedEip4844Transaction(allocator, serialized) },
        .london => return .{ .london = try parseSignedEip1559Transaction(allocator, serialized) },
        .berlin => return .{ .berlin = try parseSignedEip2930Transaction(allocator, serialized) },

        .deposit,
        .legacy,
        => return error.InvalidTransactionType,

        _ => return .{ .legacy = try parseSignedLegacyTransaction(allocator, serialized) },
    }
}
/// Parses unsigned serialized eip7702 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip7702Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!Eip7702TransactionEnvelopeSigned {
    if (serialized[0] != 4)
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
    const authorization_list,
    const v, 
    const r, 
    const s = try rlp.decodeRlp(Eip7702EnvelopeSigned, allocator, serialized[1..]);
    // zig fmt: on

    const list = try parseAccessList(allocator, access_list);
    const auth_list = try parseAuthorizationList(allocator, authorization_list);

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
        .authorizationList = auth_list,
        .v = v,
        .r = r,
        .s = s,
    };
}
/// Parses signed serialized eip1559 transactions. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseSignedEip4844Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!CancunTransactionEnvelopeSigned {
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
    const s = try rlp.decodeRlp(CancunEnvelopeSigned, allocator, serialized[1..]);
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
pub fn parseSignedEip1559Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LondonTransactionEnvelopeSigned {
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
    const s = try rlp.decodeRlp(LondonEnvelopeSigned, allocator, serialized[1..]);
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
pub fn parseSignedEip2930Transaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!BerlinTransactionEnvelopeSigned {
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
    const s = try rlp.decodeRlp(BerlinEnvelopeSigned, allocator,  serialized[1..]);
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
pub fn parseSignedLegacyTransaction(allocator: Allocator, serialized: []const u8) ParseTransactionErrors!LegacyTransactionEnvelopeSigned {
    if (serialized[0] < 0xc0)
        return error.InvalidTransactionType;

    // zig fmt: off
    const nonce, 
    const gas_price, 
    const gas,
    const address,
    const value,
    const data,
    const v,
    const r,
    const s = try rlp.decodeRlp(LegacyEnvelopeSigned, allocator,  serialized);
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
pub fn parseAccessList(allocator: Allocator, access_list: []const StructToTupleType(AccessList)) Allocator.Error![]const AccessList {
    var list = try std.array_list.Managed(AccessList).initCapacity(allocator, access_list.len);
    errdefer list.deinit();

    for (access_list) |item| {
        const address, const storage_keys = item;

        list.appendAssumeCapacity(.{ .address = address, .storageKeys = storage_keys });
    }

    return try list.toOwnedSlice();
}
/// Parses serialized transaction accessLists. Recommend to use an arena or similar otherwise its expected to leak memory.
pub fn parseAuthorizationList(allocator: Allocator, auth_list: []const StructToTupleType(AuthorizationPayload)) Allocator.Error![]const AuthorizationPayload {
    var list = try std.array_list.Managed(AuthorizationPayload).initCapacity(allocator, auth_list.len);
    errdefer list.deinit();

    for (auth_list) |item| {
        // zig fmt: off
        const chainId, 
        const address,
        const nonce,
        const y_parity,
        const r,
        const s = item;
        // zig fmt: on

        list.appendAssumeCapacity(.{
            .chain_id = chainId,
            .address = address,
            .nonce = nonce,
            .y_parity = y_parity,
            .r = r,
            .s = s,
        });
    }

    return list.toOwnedSlice();
}
