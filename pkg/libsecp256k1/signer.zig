const std = @import("std");
const c = @import("c.zig");

// Types
const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Secp256k1 = std.crypto.ecc.Secp256k1;
const Signature = @import("signature.zig").Signature;

pub const PublicKeyLength = (Secp256k1.scalar.encoded_length * 2) + 1;

pub const SignerErrors = error{ FailedToSerializePubKey, FailedToRecoverPublicKey, FailedToRecoverSignature, FailedToInitializeContext, FailedToCalcutatePubKeyFromPrivKey } || Allocator.Error;

// Signing context
context: ?*c.secp256k1_context,
// Private key in bytes
private_key: [Secp256k1.scalar.encoded_length]u8,
// Public key in bytes
public_key: [PublicKeyLength]u8,

const Signer = @This();

/// Iniates the signer and creates the needed context and the public key.
pub fn init(key: []const u8) !Signer {
    const context = c.secp256k1_context_create(c.SECP256K1_CONTEXT_SIGN | c.SECP256K1_CONTEXT_VERIFY) orelse return error.FailedToInitializeContext;
    errdefer c.secp256k1_context_destroy(context);

    const priv = if (std.mem.startsWith(u8, key, "0x")) key[2..] else key;
    var key_bytes: [32]u8 = undefined;

    _ = try std.fmt.hexToBytes(key_bytes[0..], priv);
    var pub_key: c.secp256k1_pubkey = undefined;

    if (c.secp256k1_ec_pubkey_create(context, &pub_key, &key_bytes) == 0)
        return error.FailedToCalcutatePubKeyFromPrivKey;

    var public_key: [65]u8 = undefined;
    var public_key_len = public_key.len;
    public_key[0] = 4;

    if (c.secp256k1_ec_pubkey_serialize(context, &public_key, &public_key_len, &pub_key, c.SECP256K1_EC_UNCOMPRESSED) == 0)
        return error.FailedToSerializePubKey;

    return Signer{
        .context = context,
        .private_key = key_bytes[0..32].*,
        .public_key = public_key,
    };
}

/// Destroys the signing context
pub fn deinit(self: Signer) void {
    c.secp256k1_context_destroy(self.context);
}
/// Generates a random signer based on scalar from the secp256k1 curve.
pub fn generateRandomSigner() !Signer {
    const context = c.secp256k1_context_create(c.SECP256K1_CONTEXT_SIGN | c.SECP256K1_CONTEXT_VERIFY) orelse return error.FailedToInitializeContext;
    errdefer c.secp256k1_context_destroy(context);

    const private_key = std.crypto.ecc.Secp256k1.scalar.random(.big);
    var pub_key: c.secp256k1_pubkey = undefined;

    if (c.secp256k1_ec_pubkey_create(context, &pub_key, &private_key) == 0)
        return error.FailedToCalcutatePubKeyFromPrivKey;

    var public_key: [65]u8 = undefined;
    var public_key_len = public_key.len;
    public_key[0] = 4;

    if (c.secp256k1_ec_pubkey_serialize(context, &public_key, &public_key_len, &pub_key, c.SECP256K1_EC_UNCOMPRESSED) == 0)
        return error.FailedToSerializePubKey;

    return .{ .context = context, .private_key = private_key, .public_key = public_key };
}
/// Gets the signer ethereum address from a public key.
pub fn getAddressFromPublicKey(self: Signer) ![20]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(self.public_key[1..], &hash, .{});

    return hash[12..].*;
}
/// Signs a message. The messages must be hashed beforehand.
pub fn sign(self: Signer, message_hash: [32]u8) !Signature {
    if (c.secp256k1_ec_seckey_verify(self.context, &self.private_key) != 1)
        return error.InvalidKey;

    const noncefunc = c.secp256k1_nonce_function_rfc6979;
    var sig_struct: c.secp256k1_ecdsa_recoverable_signature = undefined;

    if (c.secp256k1_ecdsa_sign_recoverable(self.context, &sig_struct, &message_hash, &self.private_key, noncefunc, null) == 0)
        return error.SignFailed;

    var sig: [PublicKeyLength]u8 = undefined;
    var rec_id: c_int = undefined;

    _ = c.secp256k1_ecdsa_recoverable_signature_serialize_compact(self.context, &sig, &rec_id, &sig_struct);

    if (rec_id >= 4)
        return error.InvalidRecoveryId;

    return .{ .r = sig[0..32].*, .s = sig[32..64].*, .v = @intCast(rec_id) };
}
/// Recovers a public key from a message and signature.
/// The message must be hash beforehand.
pub fn recoverPublicKey(message_hash: [32]u8, signature: Signature) ![PublicKeyLength]u8 {
    if (signature.v >= 4)
        return error.InvalidRecoveryId;

    const context = c.secp256k1_context_create(c.SECP256K1_CONTEXT_SIGN | c.SECP256K1_CONTEXT_VERIFY) orelse return error.FailedToInitializeContext;
    defer c.secp256k1_context_destroy(context);

    var public_key: [PublicKeyLength]u8 = undefined;
    var sig_bytes = signature.toBytes();

    var struct_pub: c.secp256k1_pubkey = undefined;
    var sig_rec: c.secp256k1_ecdsa_recoverable_signature = undefined;

    if (c.secp256k1_ecdsa_recoverable_signature_parse_compact(context, &sig_rec, sig_bytes[0..64], sig_bytes[64]) == 0)
        return error.FailedToRecoverSignature;

    if (c.secp256k1_ecdsa_recover(context, &struct_pub, &sig_rec, &message_hash) == 0)
        return error.FailedToRecoverPublicKey;

    var key_len: usize = 65;
    if (c.secp256k1_ec_pubkey_serialize(context, &public_key, &key_len, &struct_pub, c.SECP256K1_EC_UNCOMPRESSED) == 0)
        return error.FailedToSerializePubKey;

    return public_key;
}
/// Recovers ethereum address from a message and signature.
/// The message must be hash beforehand.
/// The recovered address will already be checksumed.
pub fn recoverEthereumAddress(message_hash: [32]u8, signature: Signature) ![20]u8 {
    const pub_key = try recoverPublicKey(message_hash, signature);

    var hash: [32]u8 = undefined;
    Keccak256.hash(pub_key[1..], &hash, .{});

    return hash[12..].*;
}
/// Its the same as `recoverEthereumAddress` but the original message is
/// not hashed beforehand. This will take care of it.
pub fn recoverMessageAddress(message: []const u8, signature: Signature) ![20]u8 {
    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(message, &hashed, .{});

    return recoverEthereumAddress(hashed, signature);
}
/// Signs an ethereum message. Follows the specification so it prepends
/// \x19Ethereum Signed Message:\n to the start of the message.
///
/// No need to free the allocated memory.
pub fn signMessage(self: Signer, alloc: Allocator, message: []const u8) !Signature {
    const start = "\x19Ethereum Signed Message:\n";
    const len = try std.fmt.allocPrint(alloc, "{d}", .{message.len});
    defer alloc.free(len);

    const concated = try std.mem.concat(alloc, u8, &.{ start, len, message });
    defer alloc.free(concated);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(concated, &hash, .{});

    return self.sign(hash[0..].*);
}
/// Verifies if a given message was sent by the current signer.
pub fn verifyMessage(self: Signer, sig: Signature, message_hash: [32]u8) bool {
    var sig_bytes = sig.toBytes();

    var struct_pub: c.secp256k1_pubkey = undefined;
    var sig_rec: c.secp256k1_ecdsa_signature = undefined;

    if (c.secp256k1_ecdsa_signature_parse_compact(self.context, &sig_rec, sig_bytes[0..64]) == 0)
        return false;

    if (c.secp256k1_ec_pubkey_parse(self.context, &struct_pub, &self.public_key, 65) == 0)
        return false;

    return c.secp256k1_ecdsa_verify(self.context, &sig_rec, &message_hash, &struct_pub) == 1;
}
