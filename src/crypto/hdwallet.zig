//! Experimental and unaudited code. Use with caution.
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki
const std = @import("std");
const testing = std.testing;

const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;
const Secp256k1 = std.crypto.ecc.Secp256k1;

const BIP32_SECRET_KEY = "Bitcoin seed";

const HARDNED_BIT = std.math.maxInt(i32) + 1;

/// Implementation of BIP32 HDWallets
/// It doesnt have support yet for extended keys.
pub const HDWalletNode = struct {
    /// The nodes private key that is used to derive the childs private keys.
    priv_key: [32]u8,
    /// The compressed sec1 public key.
    pub_key: [33]u8,
    /// The chain code that is used to derive public keys.
    chain_code: [32]u8,

    const Node = @This();

    /// Derive a node from a mnemonic seed. Use `pbkdf2` to generate the seed.
    pub fn fromSeed(seed: [64]u8) !Node {
        var hashed: [HmacSha512.mac_length]u8 = undefined;
        HmacSha512.create(&hashed, seed[0..], BIP32_SECRET_KEY);

        const pubkey = try Secp256k1.mul(Secp256k1.basePoint, hashed[0..32].*, .big);
        const compressed_key = pubkey.toCompressedSec1();

        return .{
            .pub_key = compressed_key,
            .priv_key = hashed[0..32].*,
            .chain_code = hashed[32..64].*,
        };
    }
    /// Derive a node from a mnemonic seed and path. Use `pbkdf2` to generate the seed.
    /// The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)
    pub fn fromSeedAndPath(seed: [64]u8, path: []const u8) !Node {
        const main_node = try fromSeed(seed);

        return main_node.derivePath(path);
    }
    /// Derives a child node from a path.
    /// The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)
    pub fn derivePath(self: Node, path: []const u8) !Node {
        if (path[0] != 'm')
            return error.InvalidPath;

        var tokenize = std.mem.tokenizeAny(u8, path[1..], "/");
        var node = self;

        if (tokenize.peek() == null)
            return error.InvalidPath;

        while (tokenize.next()) |val| {
            if (val[val.len - 1] == '\'') {
                const index = try std.fmt.parseInt(u32, val[0 .. val.len - 1], 10);
                node = try node.deriveChild(index + HARDNED_BIT);
            } else {
                const index = try std.fmt.parseInt(u32, val[0..], 10);
                node = try node.deriveChild(index);
            }
        }

        return node;
    }
    /// Derive a child node based on the index
    /// If the index is higher than std.math.maxInt(u32) this will error.
    pub fn deriveChild(self: Node, index: u32) !Node {
        return if (index & HARDNED_BIT != 0) self.deriveHarnedChild(index) else self.deriveNonHarnedChild(index);
    }
    /// Castrates a HDWalletNode. This essentially returns the node without the private key.
    pub fn castrateNode(self: Node) EunuchNode {
        return .{
            .pub_key = self.pub_key,
            .chain_code = self.chain_code,
        };
    }
    /// Derive a child node if the index is hardned
    fn deriveHarnedChild(self: Node, index: u32) !Node {
        var data: [37]u8 = undefined;
        var hashed: [64]u8 = undefined;

        //Data = 0x00 || ser256(kpar) || ser32(i)
        @memcpy(data[1..33], self.priv_key[0..32]);
        data[0] = 0;
        std.mem.writeInt(u32, data[33..], index, .big);

        HmacSha512.create(&hashed, data[0..], self.chain_code[0..]);

        const public_scalar = try Secp256k1.fromSec1(self.pub_key[0..33]);
        const pubkey_scalar = try Secp256k1.mul(Secp256k1.basePoint, hashed[0..32].*, .big);
        const child_pub_key = pubkey_scalar.add(public_scalar);

        const hashed_scalar = try Secp256k1.scalar.Scalar.fromBytes(hashed[0..32].*, .big);
        const private_scalar = try Secp256k1.scalar.Scalar.fromBytes(self.priv_key, .big);
        const child_key = hashed_scalar.add(private_scalar);

        return .{
            .priv_key = child_key.toBytes(.big),
            .chain_code = hashed[32..64].*,
            .pub_key = child_pub_key.toCompressedSec1(),
        };
    }
    /// Derive a child node if the index is not hardned
    fn deriveNonHarnedChild(self: Node, index: u32) !Node {
        var data: [37]u8 = undefined;
        var hashed: [64]u8 = undefined;

        // Data = serP(Kpar) || ser32(i)
        @memcpy(data[0..33], self.pub_key[0..33]);
        std.mem.writeInt(u32, data[33..], index, .big);
        HmacSha512.create(&hashed, data[0..], self.chain_code[0..]);

        const public_scalar = try Secp256k1.fromSec1(data[0..33]);
        const pubkey_scalar = try Secp256k1.mul(Secp256k1.basePoint, hashed[0..32].*, .big);
        const child_pub_key = pubkey_scalar.add(public_scalar);

        const hashed_scalar = try Secp256k1.scalar.Scalar.fromBytes(hashed[0..32].*, .big);
        const private_scalar = try Secp256k1.scalar.Scalar.fromBytes(self.priv_key, .big);
        const child_key = hashed_scalar.add(private_scalar);

        return .{
            .priv_key = child_key.toBytes(.big),
            .chain_code = hashed[32..64].*,
            .pub_key = child_pub_key.toCompressedSec1(),
        };
    }
};

/// The EunuchNode doesn't have the private field but it
/// can still be used to derive public keys and chain codes.
pub const EunuchNode = struct {
    /// The compressed sec1 public key.
    pub_key: [33]u8,
    /// The chain code that is used to derive public keys.
    chain_code: [32]u8,

    const Node = @This();

    /// Derive a child node based on the index
    /// If the index is higher than std.math.maxInt(u32) this will error.
    /// EunuchWalletNodes cannot derive hardned nodes.
    pub fn deriveChild(self: Node, index: u32) !Node {
        if (index > comptime std.math.maxInt(i32))
            return error.InvalidIndex;

        return self.deriveNonHarnedChild(index);
    }
    /// Derives a child node from a path. This cannot derive hardned nodes.
    /// The path must follow the specification. Example: m/44/60/0/0/0 (Most common for ethereum)
    pub fn derivePath(self: Node, path: []const u8) !Node {
        if (path[0] != 'm')
            return error.InvalidPath;

        var tokenize = std.mem.tokenizeAny(u8, path[1..], "/");
        var node = self;

        if (tokenize.peek() == null)
            return error.InvalidPath;

        while (tokenize.next()) |val| {
            const index = try std.fmt.parseInt(u32, val[0..], 10);
            node = try node.deriveChild(index);
        }

        return node;
    }
    /// Derive a child node if the index is not hardned
    fn deriveNonHarnedChild(self: Node, index: u32) !Node {
        var data: [37]u8 = undefined;
        var hashed: [64]u8 = undefined;

        @memcpy(data[0..33], self.pub_key[0..33]);
        std.mem.writeInt(u32, data[33..], index, .big);
        HmacSha512.create(&hashed, data[0..], self.chain_code[0..]);

        const public_scalar = try Secp256k1.fromSec1(data[0..33]);
        const pubkey_scalar = try Secp256k1.mul(Secp256k1.basePoint, hashed[0..32].*, .big);
        const child_pub_key = pubkey_scalar.add(public_scalar);

        return .{
            .chain_code = hashed[32..64].*,
            .pub_key = child_pub_key.toCompressedSec1(),
        };
    }
};

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
