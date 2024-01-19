const std = @import("std");
const Secp256k1 = std.crypto.ecc.Secp256k1;

pub const Signature = struct {
    r: [Secp256k1.scalar.encoded_length]u8,
    s: [Secp256k1.scalar.encoded_length]u8,
    v: u2,

    pub fn fromCompact(compact: CompactSignature) Signature {
        const v = compact.yParityWithS[0] & 0x80;
        const s = compact.yParityWithS;

        if (v == 1)
            compact.yParityWithS[0] &= 0x7f;

        return .{ .r = compact.r, .s = s, .v = v };
    }

    pub fn toBytes(sig: Signature) [65]u8 {
        var signed: [65]u8 = undefined;
        @memcpy(signed[0..32], sig.r[0..]);
        @memcpy(signed[32..64], sig.s[0..]);
        signed[64] = sig.v;

        return signed;
    }

    pub fn toHex(alloc: std.mem.Allocator, sig: Signature) ![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(bytes[0..])});
    }

    pub fn fromHex(hex: []const u8) Signature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 130) return error.InvalidSignature;
        var signed: [65]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        const v = rec_id: {
            if (signed[64] == 0 or signed[64] == 1) break :rec_id signed[64];

            if (signed[64] == 27) break :rec_id 0 else 1;
        };
        return .{ .r = signed[0..32], .s = signed[32..64], .v = v };
    }
};

pub const CompactSignature = struct {
    r: [Secp256k1.scalar.encoded_length]u8,
    yParityWithS: [Secp256k1.scalar.encoded_length]u8,

    pub fn toCompact(sig: Signature) CompactSignature {
        var compact: CompactSignature = undefined;

        compact.r = sig.r;
        var bytes: [Secp256k1.scalar.encoded_length]u8 = sig.s;

        if (sig.v == 1) {
            bytes[0] |= 0x80;
        }

        compact.yParityWithS = bytes;

        return compact;
    }

    pub fn toBytes(sig: CompactSignature) [Secp256k1.scalar.encoded_length * 2]u8 {
        var signed: [64]u8 = undefined;
        @memcpy(signed[0..32], sig.r[0..]);
        @memcpy(signed[32..64], sig.yParityWithS[0..]);

        return signed;
    }

    pub fn toHex(alloc: std.mem.Allocator, sig: CompactSignature) ![]u8 {
        const bytes = sig.toBytes();

        return std.fmt.allocPrint(alloc, "{s}", .{std.fmt.fmtSliceHexLower(bytes[0..])});
    }

    pub fn fromHex(hex: []const u8) CompactSignature {
        const signature = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;

        if (signature.len != 128) return error.InvalidSignature;
        var signed: [64]u8 = undefined;
        _ = try std.fmt.hexToBytes(signed[0..], signature);

        return .{
            .r = signed[0..32],
            .yParityWithS = signed[32..64],
        };
    }
};
