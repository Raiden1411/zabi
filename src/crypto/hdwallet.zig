//! Experimental and unaudited code. Use with caution.
//! Reference: https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki

const errors = std.crypto.errors;
const std = @import("std");
const testing = std.testing;

const EncodingError = errors.EncodingError;
const HmacSha512 = std.crypto.auth.hmac.sha2.HmacSha512;
const IdentityElementError = errors.IdentityElementError;
const NonCanonicalError = errors.NonCanonicalError;
const NotSquareError = errors.NotSquareError;
const Secp256k1 = std.crypto.ecc.Secp256k1;

const BIP32_SECRET_KEY = "Bitcoin seed";

const HARDNED_BIT = std.math.maxInt(i32) + 1;

pub const DerivePathErrors = std.fmt.ParseIntError || DeriveChildErrors || error{InvalidPath};

pub const DeriveChildErrors = EncodingError || NonCanonicalError || NotSquareError || IdentityElementError;

// TODO: Support extended keys.
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
    pub fn fromSeed(seed: [64]u8) IdentityElementError!Node {
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
    /// Derive a node from a mnemonic seed and path. Use `pbkdf2` to generate the seed.\
    /// The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)
    ///
    /// **Example**
    /// ```zig
    /// const seed = "test test test test test test test test test test test junk";
    /// var hashed: [64]u8 = undefined;
    /// try std.crypto.pwhash.pbkdf2(&hashed, seed, "mnemonic", 2048, HmacSha512);
    ///
    /// const node = try HDWalletNode.fromSeedAndPath(hashed, "m/44'/60'/0'/0/0");
    ///
    /// const hex = try std.fmt.allocPrint(testing.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(&node.priv_key)});
    /// defer testing.allocator.free(hex);
    ///
    /// try testing.expectEqualStrings("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", hex);
    /// ```
    pub fn fromSeedAndPath(seed: [64]u8, path: []const u8) DerivePathErrors!Node {
        const main_node = try fromSeed(seed);

        return main_node.derivePath(path);
    }
    /// Derives a child node from a path.\
    /// The path must follow the specification. Example: m/44'/60'/0'/0/0 (Most common for ethereum)
    pub fn derivePath(self: Node, path: []const u8) DerivePathErrors!Node {
        if (path[0] != 'm')
            return error.InvalidPath;

        var tokenize = std.mem.tokenizeScalar(u8, path[1..], '/');
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
    /// Derive a child node based on the index.\
    /// If the index is higher than std.math.maxInt(u32) this will error.
    pub fn deriveChild(self: Node, index: u32) DeriveChildErrors!Node {
        return if (index & HARDNED_BIT != 0) self.deriveHarnedChild(index) else self.deriveNonHarnedChild(index);
    }
    /// Castrates a HDWalletNode. This essentially returns the node without the private key.
    pub fn castrateNode(self: Node) EunuchNode {
        return .{
            .pub_key = self.pub_key,
            .chain_code = self.chain_code,
        };
    }
    /// Derive a child node if the index is hardned.
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

/// The `EunuchNode` doesn't have the private field but it
/// can still be used to derive public keys and chain codes.
pub const EunuchNode = struct {
    /// The compressed sec1 public key.
    pub_key: [33]u8,
    /// The chain code that is used to derive public keys.
    chain_code: [32]u8,

    const Node = @This();

    /// Derive a child node based on the index.\
    /// If the index is higher than std.math.maxInt(u32) this will error.
    ///
    /// `EunuchNodes` cannot derive hardned nodes.
    pub fn deriveChild(self: Node, index: u32) (DeriveChildErrors || error{InvalidIndex})!Node {
        if (index > comptime std.math.maxInt(i32))
            return error.InvalidIndex;

        return self.deriveNonHarnedChild(index);
    }
    /// Derives a child node from a path. This cannot derive hardned nodes.
    ///
    /// The path must follow the specification. Example: m/44/60/0/0/0 (Most common for ethereum)
    pub fn derivePath(self: Node, path: []const u8) (DerivePathErrors || error{InvalidIndex})!Node {
        if (path[0] != 'm')
            return error.InvalidPath;

        var tokenize = std.mem.tokenizeScalar(u8, path[1..], '/');
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
