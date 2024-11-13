//! Experimental and unaudited code. Use with caution.
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki

const errors = std.crypto.errors;
const std = @import("std");
const types = @import("zabi-types").ethereum;

// Types
const Address = types.Address;
const CompressedScalar = [32]u8;
const CompressedPublicKey = [33]u8;
const EncodingError = errors.EncodingError;
const IdentityElementError = errors.IdentityElementError;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const NonCanonicalError = errors.NonCanonicalError;
const NotSquareError = errors.NotSquareError;
const Scalar = Secp256k1.scalar.Scalar;
const SchnorrSignature = @import("signature.zig").SchnorrSignature;
const Secp256k1 = std.crypto.ecc.Secp256k1;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// `hashNonce` result type.
const RBytesAndScalar = struct {
    bytes: CompressedPublicKey,
    scalar: Scalar,
};

/// BIP0340 `Schnorr` signer.
///
/// For implementation details please go to the [specification](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki#user-content-Specification)
pub const SchnorrSigner = struct {
    const Self = @This();

    /// Set of possible errors when signing a message.
    pub const SigningErrors = NotSquareError || NonCanonicalError || EncodingError ||
        IdentityElementError || error{ InvalidNonce, InvalidPrivateKey };

    /// The private key of this signer.
    private_key: CompressedScalar,
    /// The compressed version of the address of this signer.
    public_key: CompressedPublicKey,
    /// The chain address of this signer.
    address_bytes: Address,

    /// Generates a compressed public key from the provided `private_key`.
    ///
    /// If a null value is provided a random key will
    /// be generated. This is to mimic the behaviour from zig's `KeyPair` types.
    pub fn init(private_key: ?CompressedScalar) IdentityElementError!Self {
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
    /// Converts the `private_key` to a `Secp256k1` scalar.
    ///
    /// Negates the scalar if the y coordinates are odd.
    pub fn privateKeyToScalar(self: Self) (NonCanonicalError || NotSquareError || EncodingError || error{InvalidPrivateKey})!Scalar {
        const private_scalar = try Scalar.fromBytes(self.private_key, .big);
        const public_key = try Secp256k1.fromSec1(self.public_key[0..]);

        if (private_scalar.isZero())
            return error.InvalidPrivateKey;

        // Negates the scalar if y is odd because we are signing `x` only.
        if (public_key.affineCoordinates().y.isOdd()) {
            const neg = private_scalar.neg();

            return neg;
        }

        return private_scalar;
    }
    /// Generates a `Schnorr` signature for a given message.
    ///
    /// This will not verify if the generated signature is correct.
    /// Please use `verifyMessage` to make sure  that the generated signature is valid.
    pub fn signUnsafe(self: Self, message: []const u8) SigningErrors!SchnorrSignature {
        // Let d' = int(sk)
        const d_scalar = try self.privateKeyToScalar();

        // Generates the random seed.
        var random_buffer: [32]u8 = undefined;
        std.crypto.random.bytes(&random_buffer);

        // Let t be the byte-wise xor of bytes(d) and hashBIP0340/aux(a)
        const rand_hash = hashAux(random_buffer);
        const t = std.mem.readInt(u256, &rand_hash, .big) ^ std.mem.readInt(u256, &d_scalar.toBytes(.big), .big);

        var t_bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &t_bytes, t, .big);

        // Let rand = hashBIP0340/nonce(t || bytes(P) || m)
        const nonce = hashNonce(t_bytes, self.public_key[1..].*, message);

        // Let k' = int(rand) mod n
        // Let R = k'⋅G
        const kr = try nonceToScalar(nonce);

        // Let e = int(hashBIP0340/challenge(bytes(R) || bytes(P) || m)) mod n.
        const challenge = hashChallenge(kr.bytes[1..].*, self.public_key[1..].*, message);
        const e = reduceToScalar(Secp256k1.scalar.encoded_length, challenge);

        // Let sig = bytes(R) || bytes((k + ed) mod n).
        const s = e.mul(d_scalar).add(kr.scalar);

        return .{
            .r = kr.bytes[1..].*,
            .s = s.toBytes(.big),
        };
    }
    /// Generates a `Schnorr` signature for a given message.
    ///
    /// This verifies if the generated signature is valid. Otherwise an `InvalidSignature` error is returned.
    pub fn sign(self: Self, message: []const u8) (SigningErrors || error{InvalidSignature})!SchnorrSignature {
        const sig = try self.signUnsafe(message);

        if (!self.verifySignature(sig, message))
            return error.InvalidSignature;

        return sig;
    }
    /// Verifies if the provided signature was signed by `Self`.
    pub fn verifySignature(self: Self, signature: SchnorrSignature, message: []const u8) bool {
        return verifyMessage(self.public_key[1..].*, signature, message);
    }
};

/// Verifies if the provided signature was signed by the provided `x` coordinate bytes from a public key.
pub fn verifyMessage(pub_key: CompressedScalar, signature: SchnorrSignature, message: []const u8) bool {
    // Let r = int(sig[0:32])
    const r = Scalar.fromBytes(signature.r, .big) catch return false;

    // Let P = lift_x(int(pk))
    const public_key = liftX(pub_key) catch return false;

    // Let e = int(hashBIP0340/challenge(bytes(r) || bytes(P) || m))
    const challenge = hashChallenge(signature.r, public_key.toCompressedSec1()[1..].*, message);
    const e = reduceToScalar(Secp256k1.Fe.encoded_length, challenge);

    // s.G
    const sg = Secp256k1.basePoint.mulPublic(signature.s, .big) catch return false;

    // -e.P
    const epk = public_key.mulPublic(e.neg().toBytes(.little), .little) catch return false;

    // Let R = s⋅G - e⋅P.
    const vr = sg.add(epk);

    // R(x)
    const vrx = reduceToScalar(Secp256k1.Fe.encoded_length, vr.affineCoordinates().x.toBytes(.big));

    // Returs false if R(y) is isOdd and r != R(x)
    return !vr.affineCoordinates().y.isOdd() and r.equivalent(vrx);
}
/// Extracts a point from the `Secp256k1` curve based on the provided `x` coordinates from
/// a `CompressedPublicKey` array of bytes.
pub fn liftX(encoded: CompressedScalar) (NonCanonicalError || NotSquareError)!Secp256k1 {
    const x = try Secp256k1.Fe.fromBytes(encoded[0..32].*, .big);

    // Let c = x3 + 7 mod p.
    const x3 = Secp256k1.B.add(x.pow(u256, 3));

    // Let y = c(p+1)/4 mod p.
    const sqrt = try x3.sqrt();

    // Return the unique point P such that x(P) = x and y(P) = y if y mod 2 = 0 or y(P) = p-y otherwise.
    const y = if (sqrt.isOdd()) sqrt.neg() else sqrt;

    return Secp256k1{ .x = x, .y = y };
}
/// Generates the auxiliary hash from a random set of bytes.
pub fn hashAux(random_buffer: [32]u8) CompressedScalar {
    var tag_hash: [32]u8 = undefined;
    Sha256.hash("BIP0340/aux", &tag_hash, .{});

    var hash: [32]u8 = undefined;

    var sha = Sha256.init(.{});
    sha.update(tag_hash[0..]);
    sha.update(tag_hash[0..]);
    sha.update(random_buffer[0..]);
    sha.final(&hash);

    return hash;
}
/// Generates the `k` value from the mask of the `aux` hash and a `public_key` with the `message`.
pub fn hashNonce(t: [32]u8, public_key: [32]u8, message: []const u8) CompressedScalar {
    var tag_hash: [32]u8 = undefined;
    Sha256.hash("BIP0340/nonce", &tag_hash, .{});

    var hash: [32]u8 = undefined;

    var sha = Sha256.init(.{});
    sha.update(tag_hash[0..]);
    sha.update(tag_hash[0..]);
    sha.update(t[0..]);
    sha.update(public_key[0..]);
    sha.update(message);
    sha.final(&hash);

    return hash;
}
/// Generates the `Schnorr` challenge from `R` bytes, `public_key` and the `message` to sign.
pub fn hashChallenge(k_r: [32]u8, pub_key: [32]u8, message: []const u8) CompressedScalar {
    var tag_hash: [32]u8 = undefined;
    Sha256.hash("BIP0340/challenge", &tag_hash, .{});

    var hash: [32]u8 = undefined;

    var sha = Sha256.init(.{});
    sha.update(tag_hash[0..]);
    sha.update(tag_hash[0..]);
    sha.update(k_r[0..]);
    sha.update(pub_key[0..]);
    sha.update(message);
    sha.final(&hash);

    return hash;
}
/// Generates the `k` scalar and bytes from a given `public_key` with the identifier.
pub fn nonceToScalar(bytes: CompressedScalar) (NonCanonicalError || IdentityElementError || error{InvalidNonce})!RBytesAndScalar {
    const private_scalar = try Scalar.fromBytes(bytes, .big);
    const public_key = try Secp256k1.basePoint.mul(bytes, .big);

    if (private_scalar.isZero())
        return error.InvalidNonce;

    // Negates the scalar if y is odd because we are signing `x` only.
    if (public_key.affineCoordinates().y.isOdd()) {
        const neg = private_scalar.neg();

        return .{
            .bytes = public_key.toCompressedSec1(),
            .scalar = neg,
        };
    }

    return .{
        .bytes = public_key.toCompressedSec1(),
        .scalar = private_scalar,
    };
}

/// Reduce the coordinate of a field element to the scalar field.
/// Copied from zig std as it's not exposed.
fn reduceToScalar(comptime unreduced_len: usize, s: [unreduced_len]u8) Scalar {
    if (unreduced_len >= 48) {
        var xs = [_]u8{0} ** 64;
        @memcpy(xs[xs.len - s.len ..], s[0..]);
        return Scalar.fromBytes64(xs, .big);
    }
    var xs = [_]u8{0} ** 48;
    @memcpy(xs[xs.len - s.len ..], s[0..]);
    return Scalar.fromBytes48(xs, .big);
}
