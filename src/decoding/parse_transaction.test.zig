const abi = @import("../abi/abi.zig");
const human = @import("../human-readable/abi_parsing.zig");
const parse = @import("parse_transaction.zig");
const serialize = @import("../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const utils = @import("../utils/utils.zig");

// Types
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const BerlinTransactionEnvelopeSigned = transaction.BerlinTransactionEnvelopeSigned;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const CancunTransactionEnvelopeSigned = transaction.CancunTransactionEnvelopeSigned;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LegacyTransactionEnvelopeSigned = transaction.LegacyTransactionEnvelopeSigned;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const LondonTransactionEnvelopeSigned = transaction.LondonTransactionEnvelopeSigned;
const Signature = @import("../crypto/signature.zig").Signature;
const Signer = @import("../crypto/Signer.zig");

// Functions
const parseTransaction = parse.parseTransaction;
const parseSignedTransaction = parse.parseSignedTransaction;
const parseEip1559Transaction = parse.parseEip1559Transaction;
const parseSignedEip1559Transaction = parse.parseSignedEip1559Transaction;
const parseEip2930Transaction = parse.parseEip2930Transaction;
const parseSignedEip2930Transaction = parse.parseSignedEip2930Transaction;
const parseEip4844Transaction = parse.parseEip4844Transaction;
const parseSignedEip4844Transaction = parse.parseSignedEip4844Transaction;

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
