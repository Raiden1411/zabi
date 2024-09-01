const meta = @import("../meta/utils.zig");
const std = @import("std");
const rlp = @import("rlp.zig");
const transaction = @import("../types/transaction.zig");
const testing = std.testing;
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");
const kzg = @import("c-kzg-4844");

// Types
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const BerlinEnvelope = transaction.BerlinEnvelope;
const BerlinEnvelopeSigned = transaction.BerlinEnvelopeSigned;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const Blob = kzg.KZG4844.Blob;
const CancunEnvelope = transaction.CancunEnvelope;
const CancunEnvelopeSigned = transaction.CancunEnvelopeSigned;
const CancunSignedWrapper = transaction.CancunSignedWrapper;
const CancunWrapper = transaction.CancunWrapper;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const Hash = types.Hash;
const Hex = types.Hex;
const KZG4844 = kzg.KZG4844;
const KZGCommitment = kzg.KZG4844.KZGCommitment;
const KZGProof = kzg.KZG4844.KZGProof;
const LegacyEnvelope = transaction.LegacyEnvelope;
const LegacyEnvelopeSigned = transaction.LegacyEnvelopeSigned;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LondonEnvelope = transaction.LondonEnvelope;
const LondonEnvelopeSigned = transaction.LondonEnvelopeSigned;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const RlpEncodeErrors = rlp.RlpEncodeErrors;
const Sidecar = kzg.KZG4844.Sidecar;
const Sidecars = kzg.KZG4844.Sidecars;
const Signature = @import("../crypto/signature.zig").Signature;
const Signer = @import("../crypto/Signer.zig");
const StructToTupleType = meta.StructToTupleType;
const TransactionEnvelope = transaction.TransactionEnvelope;
const Tuple = std.meta.Tuple;

/// Set of possible errors when serializing a transaction.
pub const SerializeErrors = RlpEncodeErrors || error{InvalidRecoveryId};

/// Main function to serialize transactions.
///
/// Supports cancun, london, berlin and legacy transaction envelopes.\
/// This uses the underlaying rlp encoding to serialize the transaction and takes an optional `Signature` in case
/// you want to serialize with the transaction signed.
///
/// For cancun transactions with blobs use the `serializeCancunTransactionWithBlobs` or `serializeCancunTransactionWithSidecars` functions.\
///
/// **Example**
/// ```zig
/// const to = try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
/// const base_legacy = try serializeTransaction(testing.allocator, .{
///     .legacy = .{
///         .nonce = 69,
///         .gasPrice = try utils.parseGwei(2),
///         .gas = 0,
///         .to = to,
///         .value = try utils.parseEth(1),
///         .data = null,
///     },
/// }, null);
/// defer testing.allocator.free(base_legacy);
/// ```
pub fn serializeTransaction(allocator: Allocator, tx: TransactionEnvelope, sig: ?Signature) SerializeErrors![]u8 {
    return switch (tx) {
        .berlin => |val| try serializeTransactionEIP2930(allocator, val, sig),
        .cancun => |val| try serializeCancunTransaction(allocator, val, sig),
        .legacy => |val| try serializeTransactionLegacy(allocator, val, sig),
        .london => |val| try serializeTransactionEIP1559(allocator, val, sig),
    };
}
/// Serializes a cancun type transactions without blobs.
///
/// Please use `serializeCancunTransactionWithSidecars` or
/// `serializeCancunTransactionWithBlobs` if you want to
/// serialize them as a wrapper.
pub fn serializeCancunTransaction(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    const blob_hashes: []const Hash = tx.blobVersionedHashes orelse &.{};

    if (sig) |signature| {
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
            signature.r,
            signature.s,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_signed});
        defer allocator.free(encoded_sig);

        var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
        // Add the transaction type
        serialized[0] = 3;
        @memcpy(serialized[1..], encoded_sig);

        return serialized;
    }

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
    };

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    var serialized = try allocator.alloc(u8, encoded.len + 1);
    // Add the transaction type
    serialized[0] = 3;
    @memcpy(serialized[1..], encoded);

    return serialized;
}
/// Serializes a cancun sidecars into the eip4844 wrapper.
pub fn serializeCancunTransactionWithBlobs(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature, blobs: []const Blob, trusted_setup: *KZG4844) ![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    const commitments = try trusted_setup.blobsToKZGCommitment(allocator, blobs);
    defer allocator.free(commitments);

    const proofs = try trusted_setup.blobsToKZGProofs(allocator, blobs, commitments);
    defer allocator.free(proofs);

    const blob_hashes = tx.blobVersionedHashes orelse try trusted_setup.commitmentsToVersionedHash(allocator, commitments, null);

    if (sig) |signature| {
        const envelope_signed: CancunSignedWrapper = .{
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
            signature.r,
            signature.s,
            blobs,
            commitments,
            proofs,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_signed});
        defer allocator.free(encoded_sig);

        var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
        // Add the transaction type
        serialized[0] = 3;
        @memcpy(serialized[1..], encoded_sig);

        return serialized;
    }

    const envelope: CancunWrapper = .{
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
        blobs,
        commitments,
        proofs,
    };

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    var serialized = try allocator.alloc(u8, encoded.len + 1);
    // Add the transaction type;
    serialized[0] = 3;
    @memcpy(serialized[1..], encoded);

    return serialized;
}
/// Serializes a cancun sidecars into the eip4844 wrapper.
pub fn serializeCancunTransactionWithSidecars(allocator: Allocator, tx: CancunTransactionEnvelope, sig: ?Signature, sidecars: Sidecars) ![]u8 {
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
        const envelope_signed: CancunSignedWrapper = .{
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
            signature.r,
            signature.s,
            list_sidecar.items(.blob),
            commitments,
            list_sidecar.items(.proof),
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_signed});
        defer allocator.free(encoded_sig);

        var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
        // Add the transaction type;
        serialized[0] = 3;
        @memcpy(serialized[1..], encoded_sig);

        return serialized;
    }

    const envelope: CancunWrapper = .{
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

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    var serialized = try allocator.alloc(u8, encoded.len + 1);
    // Add the transaction type;
    serialized[0] = 3;
    @memcpy(serialized[1..], encoded);

    return serialized;
}
/// Function to serialize eip1559 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP1559(allocator: Allocator, tx: LondonTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    if (sig) |signature| {
        const envelope_sig: LondonEnvelopeSigned = .{
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            prep_access,
            signature.v,
            signature.r,
            signature.s,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_sig});
        defer allocator.free(encoded_sig);

        var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
        // Add the transaction type;
        serialized[0] = 2;
        @memcpy(serialized[1..], encoded_sig);

        return serialized;
    }

    const envelope: LondonEnvelope = .{
        tx.chainId,
        tx.nonce,
        tx.maxPriorityFeePerGas,
        tx.maxFeePerGas,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
        prep_access,
    };

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    var serialized = try allocator.alloc(u8, encoded.len + 1);
    // Add the transaction type;
    serialized[0] = 2;
    @memcpy(serialized[1..], encoded);

    return serialized;
}
/// Function to serialize eip2930 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP2930(allocator: Allocator, tx: BerlinTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    if (sig) |signature| {
        const envelope_sig: BerlinEnvelopeSigned = .{
            tx.chainId,
            tx.nonce,
            tx.gasPrice,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            prep_access,
            signature.v,
            signature.r,
            signature.s,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_sig});
        defer allocator.free(encoded_sig);

        var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
        // Add the transaction type;
        serialized[0] = 1;
        @memcpy(serialized[1..], encoded_sig);

        return serialized;
    }

    const envelope: BerlinEnvelope = .{
        tx.chainId,
        tx.nonce,
        tx.gasPrice,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
        prep_access,
    };

    const encoded = try rlp.encodeRlp(allocator, .{envelope});
    defer allocator.free(encoded);

    var serialized = try allocator.alloc(u8, encoded.len + 1);
    // Add the transaction type;
    serialized[0] = 1;
    @memcpy(serialized[1..], encoded);

    return serialized;
}
/// Function to serialize legacy transactions.
/// Caller ownes the memory
pub fn serializeTransactionLegacy(allocator: Allocator, tx: LegacyTransactionEnvelope, sig: ?Signature) SerializeErrors![]u8 {
    if (sig) |signature| {
        const v: usize = chainId: {
            if (tx.chainId > 0) break :chainId @intCast((tx.chainId * 2) + (35 + @as(u8, @intCast(signature.v))));

            if (signature.v > 35) {
                const infer_chainId = (signature.v - 35) / 2;

                if (infer_chainId > 0) break :chainId signature.v;

                break :chainId 27 + (if (signature.v == 35) 0 else 1);
            }

            const v = 27 + @as(u8, @intFromBool(signature.v != 0));

            if (@as(u8, @intCast(signature.v)) + 27 != v)
                return error.InvalidRecoveryId;

            break :chainId v;
        };

        const envelope_sig: LegacyEnvelopeSigned = .{
            tx.nonce,
            tx.gasPrice,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            v,
            signature.r,
            signature.s,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_sig});

        return encoded_sig;
    }

    // EIP - 155
    if (tx.chainId > 0) {
        const envelope_sig: LegacyEnvelopeSigned = .{
            tx.nonce,
            tx.gasPrice,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            tx.chainId,
            null,
            null,
        };

        const encoded_sig = try rlp.encodeRlp(allocator, .{envelope_sig});

        return encoded_sig;
    }

    // Homestead unprotected
    const envelope: LegacyEnvelope = .{
        tx.nonce,
        tx.gasPrice,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
    };

    const encoded = try rlp.encodeRlp(allocator, .{envelope});

    return encoded;
}
/// Serializes the access list into a slice of tuples of hex values.
pub fn prepareAccessList(allocator: Allocator, access_list: []const AccessList) Allocator.Error![]const StructToTupleType(AccessList) {
    var tuple_list = std.ArrayList(StructToTupleType(AccessList)).init(allocator);
    errdefer tuple_list.deinit();

    for (access_list) |access| {
        try tuple_list.append(.{ access.address, access.storageKeys });
    }

    return try tuple_list.toOwnedSlice();
}
