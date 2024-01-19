const serialize = @import("serialize.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Chains = types.PublicChains;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const PubClient = @import("client.zig");
const Signature = Signer.Signature;
const Signer = @import("secp256k1").Signer;

const Wallet = @This();

alloc: Allocator,

arena: *ArenaAllocator,

pub_client: *PubClient,

signer: Signer,

pub fn init(alloc: Allocator, private_key: []const u8, url: []const u8, chain_id: ?Chains) !*Wallet {
    var wallet = try alloc.create(Wallet);
    errdefer alloc.destroy(wallet);

    wallet.arena = try alloc.create(ArenaAllocator);
    errdefer alloc.destroy(wallet.arena);

    wallet.arena.* = ArenaAllocator.init(alloc);

    const client = try PubClient.init(alloc, url, chain_id);
    const signer = try Signer.init(private_key);

    wallet.pub_client = client;
    wallet.alloc = wallet.arena.allocator();
    wallet.signer = signer;

    return wallet;
}

pub fn initFromRandomKey(alloc: Allocator, url: []const u8, chain_id: ?Chains) !*Wallet {
    var wallet = try alloc.create(Wallet);
    errdefer alloc.destroy(wallet);

    wallet.arena = try alloc.create(ArenaAllocator);
    errdefer alloc.destroy(wallet.arena);

    wallet.arena.* = ArenaAllocator.init(alloc);

    const client = try PubClient.init(alloc, url, chain_id);
    const signer = try Signer.generateRandomSigner();

    wallet.pub_client = client;
    wallet.alloc = wallet.arena.allocator();
    wallet.signer = signer;

    return wallet;
}

pub fn deinit(self: *Wallet) void {
    self.pub_client.deinit();

    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
    allocator.destroy(self);
}

pub fn signEthereumMessage(self: *Wallet, message: []const u8) !Signature {
    return try self.signer.signMessage(message);
}

pub fn verifyMessage(self: *Wallet, sig: Signature, message: []const u8) bool {
    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(message, &hash_buffer, .{});
    return self.signer.verifyMessage(sig, hash_buffer);
}

pub fn getWalletAddress(self: *Wallet) ![]u8 {
    const address = try self.signer.getAddressFromPublicKey();

    const hex_address_lower = std.fmt.bytesToHex(address, .lower);

    const checksum = try self.alloc.alloc(u8, 42);
    for (checksum[2..], 0..) |*c, i| {
        const char = hex_address_lower[i];

        if (try std.fmt.charToDigit(hex_address_lower[i], 16) > 7) {
            c.* = std.ascii.toUpper(char);
        } else {
            c.* = char;
        }
    }

    @memcpy(checksum[0..2], "0x");

    return checksum;
}

// pub fn prepareTransaction(self: *Wallet) !transaction.TransactionEnvelope {
//     const address = try self.getWalletAddress();
//     const nonce = try self.pub_client.getAddressTransactionCount(.{.address = address});
//     const chain_id = self.pub_client.chain_id;
//
// }

pub fn sendSignedTransaction(self: *Wallet, tx: transaction.TransactionEnvelope) !types.Hex {
    const serialized = try serialize.serializeTransaction(self.alloc, tx, null);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &hash_buffer, .{});

    const signed = try self.signer.sign(hash_buffer);
    const serialized_signed = try serialize.serializeTransaction(self.alloc, tx, signed);

    const hex = try std.fmt.allocPrint(self.alloc, "{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

    return self.pub_client.sendRawTransaction(hex);
}

// test "Placeholder" {
//     var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .anvil);
//     defer wallet.deinit();
//
//     const tx_hash = try wallet.sendSignedTransaction(.{ .eip1559 = .{ .chainId = 31337, .nonce = 0, .maxFeePerGas = try utils.parseGwei(2), .data = null, .maxPriorityFeePerGas = try utils.parseGwei(2), .gas = 21001, .value = try utils.parseEth(1), .accessList = &.{}, .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" } });
//
//     std.debug.print("HASH: {s}\n", .{tx_hash});
// }
