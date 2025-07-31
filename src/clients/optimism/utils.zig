const log = zabi_types.log;
const std = @import("std");
const testing = std.testing;
const op_transactions = @import("zabi-types").transactions;
const op_types = @import("types/types.zig");
const serialize = @import("serialize_deposit.zig");
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_types = @import("zabi-types");

const Address = types.Address;
const Allocator = std.mem.Allocator;
const DepositData = op_transactions.DepositData;
const DepositTransaction = op_transactions.DepositTransaction;
const Domain = op_types.Domain;
const GetDepositArgs = op_types.GetDepositArgs;
const Hash = types.Hash;
const Hex = types.Hex;
const Logs = log.Logs;
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// This expects that the data was already decoded from hex
pub fn opaqueToDepositData(hex_bytes: Hex) DepositData {
    comptime var position: usize = 0;

    const mint = std.mem.readInt(u256, hex_bytes[position .. position + 32], .big);
    position += 32;

    const value = std.mem.readInt(u256, hex_bytes[position .. position + 32], .big);
    position += 32;

    const gas = std.mem.readInt(u64, hex_bytes[position .. position + 8], .big);
    position += 8;

    const creation = hex_bytes[position .. position + 1][0] == 1;
    position += 1;

    const data = if (position > hex_bytes.len - 1) null else hex_bytes[position..hex_bytes.len];

    return .{
        .mint = mint,
        .value = value,
        .gas = gas,
        .creation = creation,
        .data = data,
    };
}

/// Gets the storage hash from a message hash
pub fn getWithdrawalHashStorageSlot(hash: Hash) Hash {
    var buffer: [64]u8 = [_]u8{0} ** 64;

    @memcpy(buffer[0..32], hash[0..]);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(&buffer, &hash_buffer, .{});

    return hash_buffer;
}

/// Gets the source hash from deposit transaction.
pub fn getSourceHash(domain: Domain, log_index: u256, l1_blockhash: Hash) Hash {
    var marker: [32]u8 = undefined;
    std.mem.writeInt(u256, &marker, log_index, .big);

    var deposit_id: [64]u8 = undefined;
    @memcpy(deposit_id[0..32], l1_blockhash[0..]);
    @memcpy(deposit_id[32..64], marker[0..]);

    var deposit_hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(&deposit_id, &deposit_hash, .{});

    var domain_hex: [32]u8 = undefined;
    std.mem.writeInt(u256, &domain_hex, @intFromEnum(domain), .big);

    var deposit_input: [64]u8 = undefined;
    @memcpy(deposit_input[0..32], domain_hex[0..]);
    @memcpy(deposit_input[32..64], deposit_hash[0..]);

    var input_hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(&deposit_input, &input_hash, .{});

    return input_hash;
}

/// Gets a deposit transaction based on the provided arguments.
pub fn getDepositTransaction(opts: GetDepositArgs) DepositTransaction {
    const hash = opts.source_hash orelse getSourceHash(opts.domain, opts.log_index, opts.l1_blockhash);

    const opaque_data = opaqueToDepositData(opts.opaque_data);
    const to = if (opaque_data.creation) null else opts.to;

    return .{
        .sourceHash = hash,
        .data = opaque_data.data,
        .to = to,
        .gas = opaque_data.gas,
        .isSystemTx = false,
        .value = opaque_data.value,
        .mint = opaque_data.mint,
        .from = opts.from,
    };
}

/// Gets a L2 transaction hash from a deposit transaction.
pub fn getL2HashFromL1DepositInfo(allocator: Allocator, opts: GetDepositArgs) !Hash {
    const deposit_tx = getDepositTransaction(opts);

    const serialized = try serialize.serializeDepositTransaction(allocator, deposit_tx);
    defer allocator.free(serialized);

    var buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &buffer, .{});

    return buffer;
}
