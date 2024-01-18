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

    pub fn signatureToBytes(sig: Signature) [65]u8 {
        var signed: [65]u8 = undefined;
        @memcpy(signed[0..32], sig.r[0..]);
        @memcpy(signed[32..64], sig.s[0..]);
        signed[64] = sig.v;

        return signed;
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
};
