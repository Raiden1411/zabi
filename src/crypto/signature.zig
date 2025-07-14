const std = @import("std");

const Allocator = std.mem.Allocator;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Secp256k1 = std.crypto.ecc.Secp256k1;

/// Zig representation of an ERC-7816 schnorr signature.
pub const EthereumSchnorrSignature = struct {
    // Generated R value from random nonce.
    r: Secp256k1,
    s: [32]u8,

    /// Converts this signature into it's compressed format.
    pub fn toCompressed(sig: EthereumSchnorrSignature) CompressedEthereumSchnorrSignature {
        const r_bytes = sig.r.toCompressedSec1();

        var hash: [32]u8 = undefined;
        Keccak256.hash(r_bytes[1..], &hash, .{});

        return .{
            .r = hash[12..].*,
            .s = sig.s,
        };
    }
    /// Converts the signature into a byte stream.
    /// [s 32 bytes][x 32 bytes][y 32 bytes]
    pub fn toBytes(sig: EthereumSchnorrSignature) [96]u8 {
        var bytes: [96]u8 = undefined;

        @memcpy(bytes[0..32], sig.s[0..]);
        @memcpy(bytes[32..64], sig.r.x.toBytes(.big)[0..]);
        @memcpy(bytes[64..96], sig.r.y.toBytes(.big)[0..]);

        return bytes;
    }
    /// Converts a byte stream of [s 32 bytes][x 32 bytes][y 32 bytes]
    /// to the represented structure.
    pub fn fromBytes(sig: [96]u8) EthereumSchnorrSignature {
        const r = Secp256k1{ .x = sig[32..64].*, .y = sig[64..96].* };

        return .{
            .r = r,
            .s = sig[0..32].*,
        };
    }
    /// Converts the struct signature into a hex string.
    ///
    /// Caller owns the memory
    pub fn toHex(sig: EthereumSchnorrSignature, allocator: Allocator) Allocator.Error![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{x}", .{bytes[0..]});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) error{
        NoSpaceLeft,
        InvalidSignature,
        InvalidLength,
        InvalidCharacter,
    }!EthereumSchnorrSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 192)
            return error.InvalidSignature;

        var sig: [96]u8 = undefined;
        _ = try std.fmt.hexToBytes(sig[0..], signature);

        return EthereumSchnorrSignature.fromBytes(sig);
    }
};

/// Zig representation of an ERC-7816 compressed schnorr signature.
pub const CompressedEthereumSchnorrSignature = struct {
    // Generated ethereum address from `R` public key.
    r: [20]u8,
    s: [32]u8,

    /// Converts the signature into a byte stream.
    /// [s 32 bytes][x 32 bytes][y 32 bytes]
    pub fn toBytes(sig: CompressedEthereumSchnorrSignature) [52]u8 {
        var bytes: [52]u8 = undefined;

        @memcpy(bytes[0..20], sig.r[0..]);
        @memcpy(bytes[20..52], sig.s[0..]);

        return bytes;
    }
    /// Converts a byte stream of [s 32 bytes][x 32 bytes][y 32 bytes]
    /// to the represented structure.
    pub fn fromBytes(sig: [52]u8) EthereumSchnorrSignature {
        return .{
            .r = sig[0..20].*,
            .s = sig[0..32].*,
        };
    }
    /// Converts the struct signature into a hex string.
    ///
    /// Caller owns the memory
    pub fn toHex(sig: EthereumSchnorrSignature, allocator: Allocator) Allocator.Error![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{x}", .{bytes[0..]});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) error{
        NoSpaceLeft,
        InvalidSignature,
        InvalidLength,
        InvalidCharacter,
    }!CompressedEthereumSchnorrSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 104)
            return error.InvalidSignature;

        var sig: [52]u8 = undefined;
        _ = try std.fmt.hexToBytes(sig[0..], signature);

        return CompressedEthereumSchnorrSignature.fromBytes(sig);
    }
};

/// Zig representation of an bip0340 schnorr signature.
pub const SchnorrSignature = struct {
    r: [32]u8,
    s: [32]u8,

    /// Converts the struct signature into bytes.
    pub fn toBytes(sig: SchnorrSignature) [64]u8 {
        var signed: [64]u8 = undefined;

        @memcpy(signed[0..32], sig.r[0..]);
        @memcpy(signed[32..64], sig.s[0..]);

        return signed;
    }
    /// Converts the signature bytes into the struct.
    pub fn fromBytes(sig: [64]u8) SchnorrSignature {
        return .{
            .r = sig[0..32].*,
            .s = sig[32..64].*,
        };
    }
    /// Converts the struct signature into a hex string.
    ///
    /// Caller owns the memory
    pub fn toHex(sig: SchnorrSignature, allocator: Allocator) Allocator.Error![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{x}", .{bytes[0..]});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) error{
        NoSpaceLeft,
        InvalidSignature,
        InvalidLength,
        InvalidCharacter,
    }!SchnorrSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 128)
            return error.InvalidSignature;

        var signed: [64]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        return .{
            .r = signed[0..32].*,
            .s = signed[32..64].*,
        };
    }
};

/// Zig representation of an ethereum signature.
pub const Signature = struct {
    r: u256,
    s: u256,
    v: u2,

    /// Converts a `CompactSignature` into a `Signature`.
    pub fn fromCompact(compact: CompactSignature) Signature {
        const v = compact.yParityWithS[0] & 0x80;
        const s = compact.yParityWithS;

        if (v == 1)
            compact.yParityWithS[0] &= 0x7f;

        return .{ .r = compact.r, .s = s, .v = v };
    }
    /// Converts the struct signature into bytes.
    pub fn toBytes(sig: Signature) [65]u8 {
        var signed: [65]u8 = undefined;

        std.mem.writeInt(u256, signed[0..32], sig.r, .big);
        std.mem.writeInt(u256, signed[32..64], sig.s, .big);
        signed[64] = sig.v;

        return signed;
    }
    /// Converts the struct signature into a hex string.
    ///
    /// Caller owns the memory
    pub fn toHex(sig: Signature, allocator: Allocator) Allocator.Error![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{x}", .{bytes[0..]});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) error{
        NoSpaceLeft,
        InvalidSignature,
        InvalidLength,
        InvalidCharacter,
    }!Signature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 130)
            return error.InvalidSignature;

        var signed: [65]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        const v = rec_id: {
            if (signed[64] == 0 or signed[64] == 1) break :rec_id signed[64];

            if (signed[64] == 27) break :rec_id 0 else break :rec_id 1;
        };

        return .{
            .r = std.mem.readInt(u256, signed[0..32], .big),
            .s = std.mem.readInt(u256, signed[32..64], .big),
            .v = @intCast(v),
        };
    }
};

/// Zig representation of a compact ethereum signature.
pub const CompactSignature = struct {
    r: u256,
    yParityWithS: u256,

    /// Converts from a `Signature` into `CompactSignature`.
    pub fn toCompact(sig: Signature) CompactSignature {
        var compact: CompactSignature = undefined;

        compact.r = sig.r;

        var bytes: [Secp256k1.scalar.encoded_length]u8 = undefined;
        std.mem.writeInt(u256, &bytes, sig.s, .big);

        if (sig.v == 1)
            bytes[0] |= 0x80;

        compact.yParityWithS = std.mem.readInt(u256, &bytes, .big);

        return compact;
    }
    /// Converts the struct signature into bytes.
    pub fn toBytes(sig: CompactSignature) [Secp256k1.scalar.encoded_length * 2]u8 {
        var signed: [64]u8 = undefined;
        std.mem.writeInt(u256, signed[0..32], sig.r, .big);
        std.mem.writeInt(u256, signed[32..64], sig.yParityWithS, .big);

        return signed;
    }
    /// Converts the struct signature into a hex string.
    ///
    /// Caller owns the memory
    pub fn toHex(sig: CompactSignature, allocator: Allocator) Allocator.Error![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{x}", .{bytes[0..]});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) error{
        NoSpaceLeft,
        InvalidSignature,
        InvalidLength,
        InvalidCharacter,
    }!CompactSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 128)
            return error.InvalidSignature;

        var signed: [64]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        return .{
            .r = std.mem.readInt(u256, signed[0..32], .big),
            .yParityWithS = std.mem.readInt(u256, signed[32..64], .big),
        };
    }
};
