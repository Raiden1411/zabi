const signer = @import("secp256k1");
const std = @import("std");
const rlp = @import("rlp.zig");
const transaction = @import("../meta/transaction.zig");
const testing = std.testing;
const types = @import("../meta/ethereum.zig");
const utils = @import("../utils.zig");
const kzg = @import("c-kzg-4844");

// Types
const AccessList = transaction.AccessList;
const Allocator = std.mem.Allocator;
const BerlinEnvelope = transaction.BerlinEnvelope;
const BerlinEnvelopeSigned = transaction.BerlinEnvelopeSigned;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const Blob = kzg.Blob;
const CancunEnvelope = transaction.CancunEnvelope;
const CancunEnvelopeSigned = transaction.CancunEnvelopeSigned;
const CancunSignedWrapper = transaction.CancunSignedWrapper;
const CancunWrapper = transaction.CancunWrapper;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const Hex = types.Hex;
const KZG4844 = kzg.KZG4844;
const KZGCommitment = kzg.KZGCommitment;
const KZGProof = kzg.KZGProof;
const LegacyEnvelope = transaction.LegacyEnvelope;
const LegacyEnvelopeSigned = transaction.LegacyEnvelopeSigned;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LondonEnvelope = transaction.LondonEnvelope;
const LondonEnvelopeSigned = transaction.LondonEnvelopeSigned;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const Sidecar = kzg.Sidecar;
const Sidecars = kzg.Sidecar;
const Signature = signer.Signature;
const TransactionEnvelope = transaction.TransactionEnvelope;
const Tuple = std.meta.Tuple;

/// Main function to serialize transactions.
/// Support london, berlin and legacy transaction envelopes.
/// For cancun transactions with blobs use the `serializeCancunTransactionWithBlob` function. This
/// will panic if you call this with the cancun transaction envelope.
///
/// Caller ownes the memory
pub fn serializeTransaction(allocator: Allocator, tx: TransactionEnvelope, sig: ?Signature) ![]u8 {
    return switch (tx) {
        .berlin => |val| try serializeTransactionEIP2930(allocator, val, sig),
        .cancun => |val| try serializeCancunTransaction(allocator, val, sig),
        .legacy => |val| try serializeTransactionLegacy(allocator, val, sig),
        .london => |val| try serializeTransactionEIP1559(allocator, val, sig),
    };
}
/// Serializes a cancun type transactions without blobs.
///
/// Please use `serializeCancunTransactionWithBlob` or
/// `serializeCancunTransactionWithSidecars` if you want to
/// serialize them as a wrapper
pub fn serializeCancunTransaction(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature) ![]u8 {
    if (tx.type != 3)
        return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    const blob_hashes: []const Hex = tx.blobVersionedHashes orelse &.{};

    if (sig) |signature| {
        // zig fmt: off
        const envelope_signed: CancunEnvelopeSigned = .{
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            prep_access,
            tx.maxFeePerBlobGas,
            blob_hashes,
            signature.v,
            signature.r[0..],
            signature.s[0..]
        };
        // zig fmt: on

        const encoded = try rlp.encodeRlp(allocator, .{envelope_signed});
        defer allocator.free(encoded);

        return try std.mem.concat(allocator, u8, &.{ &.{tx.type}, encoded });
    }

    // zig fmt: off
    const envelope: CancunEnvelope = .{ 
        tx.chainId,
        tx.nonce, 
        tx.maxPriorityFeePerGas,
        tx.maxFeePerGas,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
        prep_access,
        tx.maxFeePerBlobGas,
        blob_hashes
    };
    // zig fmt: on

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    return try std.mem.concat(allocator, u8, &.{ &.{tx.type}, encoded });
}
pub fn serializeCancunTransactionWithSidecars(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature, sidecars: Sidecars) ![]u8 {
    if (tx.type != 3)
        return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    var list_sidecar: std.MultiArrayList(Sidecar) = .{};
    defer list_sidecar.deinit(allocator);

    for (sidecars) |sidecar| {
        try list_sidecar.append(allocator, .{ .proof = sidecar.proof, .commitment = sidecar.commitment, .blob = sidecar.blob });
    }

    const commitments = list_sidecar.items(.commitment);

    var trusted: KZG4844 = .{};
    const blob_hashes = tx.blobVersionedHashes orelse try trusted.commitmentsToVersionedHash(allocator, commitments, null);

    if (sig) |signature| {
        // zig fmt: off
        const envelope_signed: CancunEnvelopeSigned = .{
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            prep_access,
            tx.maxFeePerBlobGas,
            blob_hashes,
            signature.v,
            signature.r[0..],
            signature.s[0..],
            list_sidecar.items(.blob),
            commitments,
            list_sidecar.items(.proof),
        };
        // zig fmt: on

        const encoded = try rlp.encodeRlp(allocator, .{envelope_signed});
        defer allocator.free(encoded);

        return try std.mem.concat(allocator, u8, &.{ &.{tx.type}, encoded });
    }

    // zig fmt: off
    const envelope: CancunEnvelope = .{ 
        tx.chainId,
        tx.nonce, 
        tx.maxPriorityFeePerGas,
        tx.maxFeePerGas,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
        prep_access,
        tx.maxFeePerBlobGas,
        blob_hashes,
        list_sidecar.items(.blob),
        commitments,
        list_sidecar.items(.proof),
    };
    // zig fmt: on

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    return try std.mem.concat(allocator, u8, &.{ &.{tx.type}, encoded });
}
/// Function to serialize eip1559 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP1559(alloc: Allocator, tx: LondonTransactionEnvelope, sig: ?Signature) ![]u8 {
    if (tx.type != 2)
        return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(alloc, tx.accessList);
    defer alloc.free(prep_access);

    if (sig) |signature| {
        const envelope_sig: LondonEnvelopeSigned = .{ tx.chainId, tx.nonce, tx.maxPriorityFeePerGas, tx.maxFeePerGas, tx.gas, tx.to, tx.value, tx.data, prep_access, signature.v, signature.r[0..], signature.s[0..] };

        const encoded_sig = try rlp.encodeRlp(alloc, .{envelope_sig});
        defer alloc.free(encoded_sig);

        return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded_sig });
    }

    const envelope: LondonEnvelope = .{ tx.chainId, tx.nonce, tx.maxPriorityFeePerGas, tx.maxFeePerGas, tx.gas, tx.to, tx.value, tx.data, prep_access };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}
/// Function to serialize eip2930 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP2930(alloc: Allocator, tx: BerlinTransactionEnvelope, sig: ?Signature) ![]u8 {
    if (tx.type != 1)
        return error.InvalidTransactionType;

    const prep_access = try prepareAccessList(alloc, tx.accessList);
    defer alloc.free(prep_access);

    if (sig) |signature| {
        const envelope_sig: BerlinEnvelopeSigned = .{ tx.chainId, tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data, prep_access, signature.v, signature.r[0..], signature.s[0..] };

        const encoded_sig = try rlp.encodeRlp(alloc, .{envelope_sig});
        defer alloc.free(encoded_sig);

        return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded_sig });
    }

    const envelope: BerlinEnvelope = .{ tx.chainId, tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data, prep_access };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});
    defer alloc.free(encoded);

    return try std.mem.concat(alloc, u8, &.{ &.{tx.type}, encoded });
}
/// Function to serialize legacy transactions.
/// Caller ownes the memory
pub fn serializeTransactionLegacy(alloc: Allocator, tx: LegacyTransactionEnvelope, sig: ?Signature) ![]u8 {
    if (tx.type != 0)
        return error.InvalidTransactionType;

    if (sig) |signature| {
        const v: usize = chainId: {
            if (tx.chainId > 0) break :chainId @intCast((tx.chainId * 2) + (35 + @as(u8, @intCast(signature.v))));

            if (signature.v > 35) {
                const infer_chainId = (signature.v - 35) / 2;

                if (infer_chainId > 0) break :chainId signature.v;

                break :chainId 27 + (if (signature.v == 35) 0 else 1);
            }

            const v = 27 + (if (signature.v == 35) 0 else 1);
            if (signature.v != v) return error.InvalidRecoveryId;

            break :chainId v;
        };

        const envelope_sig: LegacyEnvelopeSigned = .{ tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data, v, signature.r[0..], signature.s[0..] };

        const encoded_sig = try rlp.encodeRlp(alloc, .{envelope_sig});

        return encoded_sig;
    }

    const envelope: LegacyEnvelope = .{ tx.nonce, tx.gasPrice, tx.gas, tx.to, tx.value, tx.data };

    const encoded = try rlp.encodeRlp(alloc, .{envelope});

    return encoded;
}
/// Serializes the access list into a slice of tuples of hex values.
pub fn prepareAccessList(alloc: Allocator, access_list: []const AccessList) ![]Tuple(&[_]type{ Hex, []const Hex }) {
    var tuple_list = std.ArrayList(Tuple(&[_]type{ types.Hex, []const types.Hex })).init(alloc);
    errdefer tuple_list.deinit();

    for (access_list) |access| {
        if (!try utils.isAddress(alloc, access.address)) return error.InvalidAddress;

        for (access.storageKeys) |keys| if (!utils.isHash(keys)) return error.InvalidHash;

        try tuple_list.append(.{ access.address, access.storageKeys });
    }

    return try tuple_list.toOwnedSlice();
}

test "Base eip 4844" {
    const base = try serializeCancunTransaction(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{}, .maxFeePerBlobGas = 0, .blobVersionedHashes = &.{"0x01adbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("03f8500145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c080e1a001adbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", hex);
}

test "Base eip 1559" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip 1559" {
    const zero = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02dd018080808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 1559" {
    const min = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 0, .maxPriorityFeePerGas = 0, .maxFeePerGas = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02c90180808080808080c0", hex);
}

test "Base eip1559 with gas" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ef01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip1559 with accessList" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f88b01458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip1559 with data" {
    const base = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f101458477359400847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip 2930" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Zero eip eip2930" {
    const zero = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01dc0180808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080c0", hex);
}

test "Minimal eip 2930" {
    const min = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01c801808080808080c0", hex);
}

test "Base eip2930 with gas" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ea0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Base eip2930 with accessList" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{.{ .address = "0x0000000000000000000000000000000000000000", .storageKeys = &.{ "0x0000000000000000000000000000000000000000000000000000000000000001", "0x0000000000000000000000000000000000000000000000000000000000000002" } }} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01f8860145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080f85bf859940000000000000000000000000000000000000000f842a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002", hex);
}

test "Base eip2930 with data" {
    const base = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234", .accessList = &.{} }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01ec0145847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234c0", hex);
}

test "Base eip legacy" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Zero eip legacy" {
    const zero = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = 0, .data = null }, null);
    defer testing.allocator.free(zero);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(zero)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da80808094f39fd6e51aad88f6f4ce6ab8827279cfffb922668080", hex);
}

test "Minimal eip legacy" {
    const min = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 0, .gasPrice = 0, .gas = 0, .to = null, .value = 0, .data = null }, null);
    defer testing.allocator.free(min);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(min)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("c6808080808080", hex);
}

test "Base legacy with gas" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("e845847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex);
}

test "Base legacy with data" {
    const base = try serializeTransactionLegacy(testing.allocator, .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 21001, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = "0x1234" }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("ea45847735940082520994f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a7640000821234", hex);
}

test "Serialize Transaction Base" {
    const base_legacy = try serializeTransaction(testing.allocator, .{ .legacy = .{ .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null } }, null);
    defer testing.allocator.free(base_legacy);

    const hex_legacy = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_legacy)});
    defer testing.allocator.free(hex_legacy);

    try testing.expectEqualStrings("e64584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080", hex_legacy);

    const base_2930 = try serializeTransaction(testing.allocator, .{ .berlin = .{ .chainId = 1, .nonce = 69, .gasPrice = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} } }, null);
    defer testing.allocator.free(base_2930);

    const hex_2930 = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base_2930)});
    defer testing.allocator.free(hex_2930);

    try testing.expectEqualStrings("01e8014584773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex_2930);

    const base = try serializeTransaction(testing.allocator, .{ .london = .{ .chainId = 1, .nonce = 69, .maxPriorityFeePerGas = try utils.parseGwei(2), .maxFeePerGas = try utils.parseGwei(2), .gas = 0, .to = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1), .data = null, .accessList = &.{} } }, null);
    defer testing.allocator.free(base);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(base)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02ed0145847735940084773594008094f39fd6e51aad88f6f4ce6ab8827279cfffb92266880de0b6b3a764000080c0", hex);
}

test "Serialize eip1559 with signature" {
    const sig = try generateSignature("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");

    const encoded = try serializeTransactionEIP1559(testing.allocator, .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("02f874827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a0d4d68c02302962fa53289fda5616c9e19a9d63b3956d63d177097143b2093e3ea025e1dd76721b4fc48eb5e2f91bf9132699036deccd45b3fa9d77b1d9b7628fb2", hex);
}

test "Serialize eip2930 with signature" {
    const sig = try generateSignature("01ec827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0");

    const encoded = try serializeTransactionEIP2930(testing.allocator, .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("01f86f827a698084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c001a0855b7b9d7f752dd108609930a5dd9ced9c131936d84d5c302a6a4edd0c50101aa075fc0c4af1cf18d5bf15a9960b1988d2fbf9ae6351a957dd572e95adbbf8c26f", hex);
}

test "Serialize legacy with signature" {
    const sig = try generateSignature("ed8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080827a698080");

    const encoded = try serializeTransactionLegacy(testing.allocator, .{ .chainId = 31337, .nonce = 0, .gasPrice = try utils.parseGwei(2), .data = null, .gas = 21001, .value = try utils.parseEth(1), .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" }, sig);
    defer testing.allocator.free(encoded);

    const hex = try std.fmt.allocPrint(testing.allocator, "{s}", .{std.fmt.fmtSliceHexLower(encoded)});
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("f86d8084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a76400008082f4f5a0a918ad4845f590df2667eceacdb621dcedf9c3efefd7f783d5f45840131c338da059a2e246acdab8cfdc51b764ec20e4a59ca1998d8a101dba01cd1cb34c1179a0", hex);
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
