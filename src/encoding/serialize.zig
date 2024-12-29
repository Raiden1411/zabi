const kzg = @import("c-kzg-4844");
const meta = @import("zabi-meta").utils;
const std = @import("std");
const rlp = @import("rlp.zig");
const transaction = zabi_types.transactions;
const testing = std.testing;
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_types = @import("zabi-types");

// Types
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const AuthorizationPayload = transaction.AuthorizationPayload;
const BerlinEnvelope = transaction.BerlinEnvelope;
const BerlinEnvelopeSigned = transaction.BerlinEnvelopeSigned;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const Blob = kzg.KZG4844.Blob;
const CancunEnvelope = transaction.CancunEnvelope;
const CancunEnvelopeSigned = transaction.CancunEnvelopeSigned;
const CancunSignedWrapper = transaction.CancunSignedWrapper;
const CancunWrapper = transaction.CancunWrapper;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const Eip7702Envelope = transaction.Eip7702Envelope;
const Eip7702EnvelopeSigned = transaction.Eip7702EnvelopeSigned;
const Eip7702TransactionEnvelope = transaction.Eip7702TransactionEnvelope;
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
const RlpEncodeErrors = rlp.RlpEncoder(std.ArrayList(u8).Writer).Error;
const Sidecar = kzg.KZG4844.Sidecar;
const Sidecars = kzg.KZG4844.Sidecars;
const Signature = @import("zabi-crypto").signature.Signature;
const StructToTupleType = meta.StructToTupleType;
const TransactionEnvelope = transaction.TransactionEnvelope;
const Tuple = std.meta.Tuple;

/// Set of possible errors when serializing a transaction.
pub const SerializeErrors = RlpEncodeErrors || error{InvalidRecoveryId};

/// Set of possible errors when serializing cancun blobs.
pub const CancunSerializeErrors = RlpEncodeErrors || Allocator.Error || error{
    SetupMustBeInitialized,
    FailedToConvertBlobToCommitment,
    FailedToComputeBlobKZGProof,
};

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
pub fn serializeTransaction(
    allocator: Allocator,
    tx: TransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
    return switch (tx) {
        .berlin => |val| try serializeTransactionEIP2930(allocator, val, sig),
        .cancun => |val| try serializeCancunTransaction(allocator, val, sig),
        .eip7702 => |val| try serializeTransactionEIP7702(allocator, val, sig),
        .legacy => |val| try serializeTransactionLegacy(allocator, val, sig),
        .london => |val| try serializeTransactionEIP1559(allocator, val, sig),
    };
}
/// Function to serialize eip7702 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP7702(
    allocator: Allocator,
    tx: Eip7702TransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    const prep_auth = try prepareAuthorizationList(allocator, tx.authorizationList);
    defer allocator.free(prep_auth);

    if (sig) |signature| {
        const envelope_signed: Eip7702EnvelopeSigned = .{
            tx.chainId,
            tx.nonce,
            tx.maxPriorityFeePerGas,
            tx.maxFeePerGas,
            tx.gas,
            tx.to,
            tx.value,
            tx.data,
            prep_access,
            prep_auth,
            signature.v,
            signature.r,
            signature.s,
        };

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x04);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_signed, list.writer());

        const serialized = try list.toOwnedSlice();
        return serialized;
    }

    const envelope_signed: Eip7702Envelope = .{
        tx.chainId,
        tx.nonce,
        tx.maxPriorityFeePerGas,
        tx.maxFeePerGas,
        tx.gas,
        tx.to,
        tx.value,
        tx.data,
        prep_access,
        prep_auth,
    };

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x04);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope_signed, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Serializes a cancun type transactions without blobs.
///
/// Please use `serializeCancunTransactionWithSidecars` or
/// `serializeCancunTransactionWithBlobs` if you want to
/// serialize them as a wrapper.
pub fn serializeCancunTransaction(
    allocator: Allocator,
    tx: CancunTransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
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

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x03);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_signed, list.writer());

        const serialized = try list.toOwnedSlice();
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

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x03);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Serializes a cancun sidecars into the eip4844 wrapper.
pub fn serializeCancunTransactionWithBlobs(
    allocator: Allocator,
    tx: CancunTransactionEnvelope,
    sig: ?Signature,
    blobs: []const Blob,
    trusted_setup: *KZG4844,
) CancunSerializeErrors![]u8 {
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

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x03);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_signed, list.writer());

        const serialized = try list.toOwnedSlice();
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

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x03);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Serializes a cancun sidecars into the eip4844 wrapper.
pub fn serializeCancunTransactionWithSidecars(
    allocator: Allocator,
    tx: CancunTransactionEnvelope,
    sig: ?Signature,
    sidecars: Sidecars,
) SerializeErrors![]u8 {
    const prep_access = try prepareAccessList(allocator, tx.accessList);
    defer allocator.free(prep_access);

    var list_sidecar: std.MultiArrayList(Sidecar) = .{};
    defer list_sidecar.deinit(allocator);

    for (sidecars) |sidecar|
        try list_sidecar.append(allocator, .{ .proof = sidecar.proof, .commitment = sidecar.commitment, .blob = sidecar.blob });

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

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x03);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_signed, list.writer());

        const serialized = try list.toOwnedSlice();
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

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x03);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Function to serialize eip1559 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP1559(
    allocator: Allocator,
    tx: LondonTransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
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

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x02);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_sig, list.writer());

        const serialized = try list.toOwnedSlice();
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

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x02);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Function to serialize eip2930 transactions.
/// Caller ownes the memory
pub fn serializeTransactionEIP2930(
    allocator: Allocator,
    tx: BerlinTransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
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

        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.writer().writeByte(0x01);
        try rlp.encodeRlpFromArrayListWriter(allocator, envelope_sig, list.writer());

        const serialized = try list.toOwnedSlice();
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

    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try list.writer().writeByte(0x01);
    try rlp.encodeRlpFromArrayListWriter(allocator, envelope, list.writer());

    const serialized = try list.toOwnedSlice();
    return serialized;
}
/// Function to serialize legacy transactions.
/// Caller ownes the memory
pub fn serializeTransactionLegacy(
    allocator: Allocator,
    tx: LegacyTransactionEnvelope,
    sig: ?Signature,
) SerializeErrors![]u8 {
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

        const encoded_sig = try rlp.encodeRlp(allocator, envelope_sig);

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

        const encoded_sig = try rlp.encodeRlp(allocator, envelope_sig);

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

    const encoded = try rlp.encodeRlp(allocator, envelope);

    return encoded;
}
/// Serializes the access list into a slice of tuples of hex values.
pub fn prepareAccessList(
    allocator: Allocator,
    access_list: []const AccessList,
) Allocator.Error![]const StructToTupleType(AccessList) {
    var tuple_list = try std.ArrayList(StructToTupleType(AccessList)).initCapacity(allocator, access_list.len);
    errdefer tuple_list.deinit();

    for (access_list) |access| {
        tuple_list.appendAssumeCapacity(.{ access.address, access.storageKeys });
    }

    return tuple_list.toOwnedSlice();
}
/// Serializes the authorization list into a slice of tuples of hex values.
pub fn prepareAuthorizationList(
    allocator: Allocator,
    authorization_list: []const AuthorizationPayload,
) Allocator.Error![]const StructToTupleType(AuthorizationPayload) {
    var tuple_list = try std.ArrayList(StructToTupleType(AuthorizationPayload)).initCapacity(allocator, authorization_list.len);
    errdefer tuple_list.deinit();

    for (authorization_list) |auth| {
        tuple_list.appendAssumeCapacity(.{ auth.chain_id, auth.address, auth.nonce, auth.y_parity, auth.r, auth.s });
    }

    return tuple_list.toOwnedSlice();
}
