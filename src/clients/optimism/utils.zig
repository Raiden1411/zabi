const log = @import("../../types/log.zig");
const std = @import("std");
const testing = std.testing;
const op_transactions = @import("types/transaction.zig");
const op_types = @import("types/types.zig");
const serialize = @import("serialize_deposit.zig");
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

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

test "Source Hash" {
    const hash = getSourceHash(.user_deposit, 196, try utils.hashToBytes("0x9ba3933dc6ce43c145349770a39c30f9b647f17668f004bd2e05c80a2e7262f7"));

    try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0xd0868c8764d81f1749edb7dec4a550966963540d9fe50aefce8cdb38ea7b2213"));
}

test "L2HashFromL1DepositInfo" {
    {
        var buffer: [512]u8 = undefined;

        const opaque_bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045000000000000520800");
        const hash = try getL2HashFromL1DepositInfo(testing.allocator, .{
            .opaque_data = opaque_bytes,
            .from = try utils.addressToBytes("0x1a1E021A302C237453D3D45c7B82B19cEEB7E2e6"),
            .to = try utils.addressToBytes("0x1a1E021A302C237453D3D45c7B82B19cEEB7E2e6"),
            .l1_blockhash = try utils.hashToBytes("0x634c52556471c589f42db9131467e0c9484f5c73049e32d1a74e2a4ce0f91d57"),
            .log_index = 109,
            .domain = .user_deposit,
        });

        try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0x0a60b983815ed475c5919609025204a479654d93afc610feca7d99ae0befc329"));
    }
    {
        var buffer: [512]u8 = undefined;

        const opaque_bytes = try std.fmt.hexToBytes(&buffer, "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000520800");
        const hash = try getL2HashFromL1DepositInfo(testing.allocator, .{
            .opaque_data = opaque_bytes,
            .from = try utils.addressToBytes("0x80B01fDEd19145FFB893123eC38eBba31b4043Ee"),
            .to = try utils.addressToBytes("0x80B01fDEd19145FFB893123eC38eBba31b4043Ee"),
            .l1_blockhash = try utils.hashToBytes("0x9375ba075993fcc3cd3f66ef1fc45687aeccc04edfc06da2bc7cdb8984046ed7"),
            .log_index = 36,
            .domain = .user_deposit,
        });

        try testing.expectEqualSlices(u8, &hash, &try utils.hashToBytes("0xb81d4b3fe43986c51d29bf29a8c68c9a301c074531d585298bc1e03df68c8459"));
    }
}

test "GetWithdrawalHashStorageSlot" {
    const slot = getWithdrawalHashStorageSlot(try utils.hashToBytes("0xB1C3824DEF40047847145E069BF467AA67E906611B9F5EF31515338DB0AABFA2"));

    try testing.expectEqualSlices(u8, &slot, &try utils.hashToBytes("0x4a932049252365b3eedbc5190e18949f2ec11f39d3bef2d259764799a1b27d99"));
}
