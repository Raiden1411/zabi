const schnorr = @import("zabi").crypto.schnorr;
const std = @import("std");
const testing = std.testing;

const EthereumSchorrSigner = schnorr.EthereumSchorrSigner;
const Schnorr = schnorr.SchnorrSigner;
const SchnorrSignature = @import("zabi").crypto.signature.SchnorrSignature;

test "Signature" {
    const key: [32]u8 = [_]u8{ 129, 67, 33, 128, 106, 189, 229, 67, 64, 108, 116, 150, 77, 15, 162, 47, 94, 199, 40, 148, 106, 225, 122, 152, 113, 177, 105, 30, 18, 13, 94, 40 };

    const signer = try Schnorr.init(key);

    _ = try signer.sign("hello");
}

test "From External" {
    // Generated from https://github.com/paulmillr/noble-curves
    const sig_bytes = [_]u8{ 97, 91, 247, 200, 55, 183, 12, 158, 163, 58, 169, 238, 105, 189, 83, 87, 111, 190, 187, 93, 97, 72, 117, 180, 188, 233, 180, 68, 105, 207, 100, 213, 34, 103, 5, 151, 218, 58, 77, 217, 74, 126, 149, 98, 37, 40, 167, 212, 239, 96, 78, 108, 202, 96, 228, 206, 226, 119, 178, 231, 161, 68, 85, 180 };

    const pub_key = [_]u8{ 91, 120, 77, 254, 147, 28, 156, 186, 240, 9, 63, 227, 214, 102, 138, 74, 77, 66, 87, 46, 73, 27, 36, 144, 229, 107, 68, 159, 16, 230, 130, 33 };

    try testing.expect(Schnorr.verifyMessage(pub_key, SchnorrSignature.fromBytes(sig_bytes), "hello"));
}

test "Invalid Signature" {
    // Grabbed from https://github.com/paulmillr/noble-curves/blob/main/test/vectors/secp256k1/schnorr.csv
    var pub_key: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&pub_key, "D69C3509BB99E412E68B0FE8544E72837DFA30746D8BE2AA65975F29D22DC7B9");

    try testing.expect(!Schnorr.verifyMessage(pub_key, try SchnorrSignature.fromHex("6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B"), "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"));
    try testing.expect(!Schnorr.verifyMessage(pub_key, try SchnorrSignature.fromHex("6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"), "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"));
    try testing.expect(!Schnorr.verifyMessage(pub_key, try SchnorrSignature.fromHex("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B"), "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"));
    try testing.expect(!Schnorr.verifyMessage(pub_key, try SchnorrSignature.fromHex("0000000000000000000000000000000000000000000000000000000000000000123DDA8328AF9C23A94C1FEECFD123BA4FB73476F0D594DCB65C6425BD186051"), "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"));
    try testing.expect(!Schnorr.verifyMessage(pub_key, try SchnorrSignature.fromHex("1FA62E331EDBC21C394792D2AB1100A7B432B013DF3F6FF4F99FCB33E0E1515F28890B3EDB6E7189B630448B515CE4F8622A954CFE545735AAEA5134FCCDB2BD"), "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89"));
}

test "Ethereum Schnorr" {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash("hello", &hash, .{});

    const key: [32]u8 = [_]u8{ 129, 67, 33, 128, 106, 189, 229, 67, 64, 108, 116, 150, 77, 15, 162, 47, 94, 199, 40, 148, 106, 225, 122, 152, 113, 177, 105, 30, 18, 13, 94, 40 };

    const signer = try EthereumSchorrSigner.init(key);
    _ = try signer.sign(hash);
}
