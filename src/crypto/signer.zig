const std = @import("std");
const types = @import("../types/ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Secp256k1 = std.crypto.ecc.Secp256k1;
const Signature = @import("signature.zig").Signature;

const Signer = @This();

/// The private key of this signer.
private_key: Hash,
/// The compressed version of the address of this signer.
public_key: [33]u8,
/// The chain address of this signer.
address_bytes: Address,

/// Recovers the public key from a message
///
/// Returns the public key in an uncompressed sec1 format so that
/// it can be used later to recover the address.
pub fn recoverPubkey(signature: Signature, message_hash: Hash) ![65]u8 {
    const z = reduceToScalar(Secp256k1.Fe.encoded_length, message_hash);

    if (z.isZero())
        return error.InvalidMessageHash;

    const s = try Secp256k1.scalar.Scalar.fromBytes(signature.s, .big);
    const r = try Secp256k1.scalar.Scalar.fromBytes(signature.r, .big);

    const r_inv = r.invert();
    const v1 = z.mul(r_inv).neg().toBytes(.little);
    const v2 = s.mul(r_inv).toBytes(.little);

    const y_is_odd = signature.v % 2 == 1;

    const vr = try Secp256k1.Fe.fromBytes(r.toBytes(.little), .little);
    const recover_id = try Secp256k1.recoverY(vr, y_is_odd);

    const curve = try Secp256k1.fromAffineCoordinates(.{ .x = vr, .y = recover_id });

    const recovered_scalar = try Secp256k1.mulDoubleBasePublic(Secp256k1.basePoint, v1, curve, v2, .little);

    return recovered_scalar.toUncompressedSec1();
}
/// Recovers the address from a message using the
/// recovered public key from the message.
pub fn recoverAddress(signature: Signature, message_hash: Hash) !Address {
    const pub_key = try recoverPubkey(signature, message_hash);

    var hash: Hash = undefined;
    Keccak256.hash(pub_key[1..], &hash, .{});

    return hash[12..].*;
}
/// Inits the signer. Generates a compressed public key from the provided
/// `private_key`. If a null value is provided a random key will
/// be generated. This is to mimic the behaviour from zig's `KeyPair` types.
pub fn init(private_key: ?Hash) !Signer {
    const key = private_key orelse Secp256k1.scalar.random(.big);

    const public_scalar = try Secp256k1.mul(Secp256k1.basePoint, key, .big);
    const public_key = public_scalar.toCompressedSec1();

    // Get the address bytes
    var hash: [32]u8 = undefined;
    Keccak256.hash(public_scalar.toUncompressedSec1()[1..], &hash, .{});

    const address: Address = hash[12..].*;

    return .{
        .private_key = key,
        .public_key = public_key,
        .address_bytes = address,
    };
}
/// Signs an ethereum or EVM like chains message.
/// Since ecdsa signatures are malliable EVM chains only accept
/// signature with low s values. We enforce this behaviour as well
/// as using RFC 6979 for generating deterministic scalars for recoverying
/// public keys from messages.
pub fn sign(self: Signer, hash: Hash) !Signature {
    const z = reduceToScalar(Secp256k1.Fe.encoded_length, hash);

    // Generates a deterministic nonce based on RFC 6979
    const k_bytes = self.generateNonce(hash);
    const k = try Secp256k1.scalar.Scalar.fromBytes(k_bytes, .big);

    // Generate R
    const p = try Secp256k1.basePoint.mul(k.toBytes(.big), .big);
    const p_affine = p.affineCoordinates();
    const xs = p_affine.x.toBytes(.big);

    // Find the yParity
    var y_int: u2 = @truncate(p_affine.y.toInt() & 1);

    const r = reduceToScalar(Secp256k1.Fe.encoded_length, xs);

    if (r.isZero())
        return error.IdentityElement;

    // Generate S
    const k_inv = k.invert();
    const zrs = z.add(r.mul(try Secp256k1.scalar.Scalar.fromBytes(self.private_key, .big)));
    var s_malliable = k_inv.mul(zrs);

    if (s_malliable.isZero())
        return error.IdentityElement;

    // Since ecdsa signatures are malliable ethereum and other
    // chains only accept signatures with low s so we need to see
    // which of the s in the curve is the lowest.
    const s_bytes = s_malliable.toBytes(.little);
    const s_scalar = std.mem.readInt(u256, &s_bytes, .little);

    // If high S then invert the yParity bits.
    if (s_scalar > Secp256k1.scalar.field_order / 2)
        y_int ^= 1;

    const s_neg_bytes = s_malliable.neg().toBytes(.little);
    const s_neg_scalar = std.mem.readInt(u256, &s_neg_bytes, .little);

    const scalar = @min(s_scalar, s_neg_scalar % Secp256k1.scalar.field_order);

    var s_buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &s_buffer, scalar, .little);

    const s = try Secp256k1.scalar.Scalar.fromBytes(s_buffer, .little);

    return .{
        .r = r.toBytes(.big),
        .s = s.toBytes(.big),
        .v = y_int,
    };
}
/// Verifies if a message was signed by this signer.
pub fn verifyMessage(self: Signer, message_hash: Hash, signature: Signature) bool {
    const z = reduceToScalar(Secp256k1.scalar.encoded_length, message_hash);

    if (z.isZero())
        return false;

    const s = Secp256k1.scalar.Scalar.fromBytes(signature.s, .big) catch return false;
    const r = Secp256k1.scalar.Scalar.fromBytes(signature.r, .big) catch return false;
    const public_scalar = Secp256k1.fromSec1(self.public_key[0..]) catch return false;

    if (public_scalar.equivalent(Secp256k1.identityElement))
        return false;

    // Copied from zig's std
    const s_inv = s.invert();
    const v1 = z.mul(s_inv).toBytes(.little);
    const v2 = r.mul(s_inv).toBytes(.little);

    const v1g = Secp256k1.basePoint.mulPublic(v1, .little) catch return false;
    const v2pk = public_scalar.mulPublic(v2, .little) catch return false;

    const vxs = v1g.add(v2pk).affineCoordinates().x.toBytes(.big);
    const vr = reduceToScalar(Secp256k1.Fe.encoded_length, vxs);

    return r.equivalent(vr);
}
/// Gets the uncompressed version of the public key
pub fn getPublicKeyUncompressed(self: Signer) [65]u8 {
    const pub_key = try Secp256k1.mul(Secp256k1.basePoint, self.private_key, .big);

    return pub_key.toUncompressedSec1();
}
/// Implementation of RFC 6979 of deterministic k values for deterministic signature generation.
/// Reference: https://datatracker.ietf.org/doc/html/rfc6979
pub fn generateNonce(self: Signer, message_hash: Hash) [32]u8 {
    // We already ask for the hashed message.
    // message_hash == h1 and x == private_key.
    // Section 3.2.a
    var v: [33]u8 = undefined;
    var k: [32]u8 = undefined;
    var buffer: [97]u8 = undefined;

    // Section 3.2.b
    @memset(v[0..32], 0x01);
    v[32] = 0x00;

    // Section 3.2.c
    @memset(&k, 0x00);

    // Section 3.2.d
    @memcpy(buffer[0..32], v[0..32]);
    buffer[32] = 0x00;

    @memcpy(buffer[33..65], &self.private_key);
    @memcpy(buffer[65..97], &message_hash);
    HmacSha256.create(&k, &buffer, &k);

    // Section 3.2.e
    HmacSha256.create(v[0..32], v[0..32], &k);

    // Section 3.2.f
    @memcpy(buffer[0..32], v[0..32]);
    buffer[32] = 0x01;

    @memcpy(buffer[33..65], &self.private_key);
    @memcpy(buffer[65..97], &message_hash);
    HmacSha256.create(&k, &buffer, &k);

    // Section 3.2.g
    HmacSha256.create(v[0..32], v[0..32], &k);

    // Section 3.2.h
    HmacSha256.create(v[0..32], v[0..32], &k);

    while (true) {
        const k_int = std.mem.readInt(u256, v[0..32], .big);

        // K is within [1,q-1] and is in R value.
        // that is not 0 so we break here.
        if (k_int > 0 and k_int < Secp256k1.scalar.field_order) {
            break;
        }

        // Keep generating until we found a valid K.
        HmacSha256.create(&k, v[0..], &k);
        HmacSha256.create(v[0..32], v[0..32], &k);
    }

    return v[0..32].*;
}

// Reduce the coordinate of a field element to the scalar field.
// Copied from zig std as it's not exposed.
fn reduceToScalar(comptime unreduced_len: usize, s: [unreduced_len]u8) Secp256k1.scalar.Scalar {
    if (unreduced_len >= 48) {
        var xs = [_]u8{0} ** 64;
        @memcpy(xs[xs.len - s.len ..], s[0..]);
        return Secp256k1.scalar.Scalar.fromBytes64(xs, .big);
    }
    var xs = [_]u8{0} ** 48;
    @memcpy(xs[xs.len - s.len ..], s[0..]);
    return Secp256k1.scalar.Scalar.fromBytes48(xs, .big);
}
