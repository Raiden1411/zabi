const std = @import("std");

const Allocator = std.mem.Allocator;
const Secp256k1 = std.crypto.ecc.Secp256k1;

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
    pub fn toHex(sig: Signature, allocator: Allocator) ![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(bytes[0..])});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) !Signature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 130) return error.InvalidSignature;
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

        if (sig.v == 1) {
            bytes[0] |= 0x80;
        }

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
    pub fn toHex(sig: CompactSignature, allocator: Allocator) ![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(bytes[0..])});
    }
    /// Converts a hex signature into it's struct representation.
    pub fn fromHex(hex: []const u8) CompactSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 128) return error.InvalidSignature;
        var signed: [64]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        return .{
            .r = std.mem.readInt(u256, signed[0..32], .big),
            .yParityWithS = std.mem.readInt(u256, signed[32..64], .big),
        };
    }
};
