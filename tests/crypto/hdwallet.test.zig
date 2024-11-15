const hdwallet = @import("zabi").crypto.hdwallet;
const std = @import("std");
const testing = std.testing;

const HDWalletNode = hdwallet.HDWalletNode;
const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;

test "Anvil/Hardhat" {
    const seed = "test test test test test test test test test test test junk";
    var hashed: [64]u8 = undefined;

    try std.crypto.pwhash.pbkdf2(&hashed, seed, "mnemonic", 2048, HmacSha512);

    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/0");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/0");
        const castrated = node.castrateNode();
        const eunuch = try castrated.derivePath("m/44/60/0/0/0");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&eunuch.pub_key)});
        defer testing.allocator.free(hex);

        try testing.expect(hex.len == 68);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/1");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/2");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/3");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/4");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/5");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/6");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/7");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/8");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97", hex);
    }
    {
        const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/9");
        const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
        defer testing.allocator.free(hex);

        try testing.expectEqualStrings("0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6", hex);
    }
}

test "Errors" {
    const seed = "test test test test test test test test test test test junk";
    var hashed: [64]u8 = undefined;

    try std.crypto.pwhash.pbkdf2(&hashed, seed, "mnemonic", 2048, HmacSha512);

    const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/0");
    try testing.expectError(error.InvalidPath, node.derivePath("foo"));
    try testing.expectError(error.InvalidPath, node.derivePath("m/"));

    const castrated = node.castrateNode();
    try testing.expectError(error.InvalidIndex, castrated.deriveChild(std.math.maxInt(u32)));
    try testing.expectError(error.InvalidCharacter, castrated.derivePath("m/44'"));
}
