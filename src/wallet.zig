const serialize = @import("serialize.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const Allocator = std.mem.Allocator;
const Anvil = @import("tests/anvil.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const Chains = types.PublicChains;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const PubClient = @import("client.zig");
const Signer = @import("secp256k1").Signer;
const Signature = @import("secp256k1").Signature;

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
    self.signer.deinit();
    self.arena.deinit();
    allocator.destroy(self.arena);
    allocator.destroy(self);
}

pub fn signEthereumMessage(self: *Wallet, alloc: Allocator, message: []const u8) !Signature {
    return try self.signer.signMessage(alloc, message);
}

pub fn getWalletAddress(self: *Wallet) ![]u8 {
    const address = try self.signer.getAddressFromPublicKey();

    const hex_address_lower = std.fmt.bytesToHex(address, .lower);

    var hashed: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(hex_address_lower[0..], &hashed, .{});
    const hex = std.fmt.bytesToHex(hashed, .lower);

    const checksum = try self.alloc.alloc(u8, 42);
    for (checksum[2..], 0..) |*c, i| {
        const char = hex_address_lower[i];

        if (try std.fmt.charToDigit(hex[i], 16) > 7) {
            c.* = std.ascii.toUpper(char);
        } else {
            c.* = char;
        }
    }

    @memcpy(checksum[0..2], "0x");

    return checksum;
}

pub fn verifyMessage(self: *Wallet, sig: Signature, message: []const u8) bool {
    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(message, &hash_buffer, .{});
    return self.signer.verifyMessage(sig, hash_buffer);
}

pub fn prepareTransaction(self: *Wallet, unprepared_envelope: transaction.PrepareEnvelope) !transaction.TransactionEnvelope {
    const address = try self.getWalletAddress();

    switch (unprepared_envelope) {
        .eip1559 => |tx| {
            if (tx.type.? != 2) return error.InvalidTransactionType;
            var request: transaction.EthCallEip1559 = .{ .from = address, .to = tx.to, .gas = tx.gas, .maxFeePerGas = tx.maxFeePerGas, .maxPriorityFeePerGas = tx.maxPriorityFeePerGas, .data = tx.data, .value = tx.value orelse 0 };

            const curr_block = try self.pub_client.getBlockByNumber(.{});
            const chain_id = tx.chainId orelse self.pub_client.chain_id;
            const accessList: []const transaction.AccessList = tx.accessList orelse &.{};

            const nonce: u64 = tx.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

            if (tx.maxFeePerGas == null or tx.maxPriorityFeePerGas == null) {
                const fees = try self.pub_client.estimateFeesPerGas(.{ .eip1559 = request }, curr_block);
                request.maxPriorityFeePerGas = tx.maxPriorityFeePerGas orelse fees.eip1559.max_priority_fee;
                request.maxFeePerGas = tx.maxFeePerGas orelse fees.eip1559.max_fee_gas;

                if (tx.maxFeePerGas) |fee| {
                    if (fee < fees.eip1559.max_priority_fee) return error.MaxFeePerGasUnderflow;
                }
            }

            if (tx.gas == null) {
                request.gas = try self.pub_client.estimateGas(.{ .eip1559 = request }, .{});
            }

            return .{ .eip1559 = .{ .chainId = chain_id, .nonce = nonce, .gas = request.gas.?, .maxFeePerGas = request.maxFeePerGas.?, .maxPriorityFeePerGas = request.maxPriorityFeePerGas.?, .data = request.data, .to = request.to, .value = request.value.?, .accessList = accessList } };
        },
        .eip2930 => |tx| {
            var request: transaction.EthCallLegacy = .{ .from = address, .to = tx.to, .gas = tx.gas, .gasPrice = tx.gasPrice, .data = tx.data, .value = tx.value orelse 0 };

            const curr_block = try self.pub_client.getBlockByNumber(.{});
            const chain_id = tx.chainId orelse self.pub_client.chain_id;
            const accessList: []const transaction.AccessList = tx.accessList orelse &.{};

            const nonce: u64 = tx.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

            if (tx.gasPrice == null) {
                const fees = try self.pub_client.estimateFeesPerGas(.{ .legacy = request }, curr_block);
                request.gasPrice = fees.legacy.gas_price;
            }

            if (tx.gas == null) {
                request.gas = try self.pub_client.estimateGas(.{ .legacy = request }, .{});
            }

            return .{ .eip2930 = .{ .chainId = chain_id, .nonce = nonce, .gas = request.gas.?, .gasPrice = request.gasPrice.?, .data = request.data, .to = request.to, .value = request.value.?, .accessList = accessList } };
        },
        .legacy => |tx| {
            var request: transaction.EthCallLegacy = .{ .from = address, .to = tx.to, .gas = tx.gas, .gasPrice = tx.gasPrice, .data = tx.data, .value = tx.value orelse 0 };

            const curr_block = try self.pub_client.getBlockByNumber(.{});
            const chain_id = tx.chainId orelse self.pub_client.chain_id;

            const nonce: u64 = tx.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

            if (tx.gasPrice == null) {
                const fees = try self.pub_client.estimateFeesPerGas(.{ .legacy = request }, curr_block);
                request.gasPrice = fees.legacy.gas_price;
            }

            if (tx.gas == null) {
                request.gas = try self.pub_client.estimateGas(.{ .legacy = request }, .{});
            }

            return .{ .legacy = .{ .chainId = chain_id, .nonce = nonce, .gas = request.gas.?, .gasPrice = request.gasPrice.?, .data = request.data, .to = request.to, .value = request.value.? } };
        },
    }
}

pub fn assertTransaction(self: *Wallet, tx: transaction.TransactionEnvelope) !void {
    switch (tx) {
        .eip1559 => |tx_eip1559| {
            if (tx_eip1559.chainId != self.pub_client.chain_id) return error.InvalidChainId;
            if (tx_eip1559.maxPriorityFeePerGas > tx_eip1559.maxFeePerGas) return error.TransactionTipToHigh;
            if (tx_eip1559.to) |addr| if (!try utils.isAddress(self.alloc, addr)) return error.InvalidAddress;
        },
        .eip2930 => |tx_eip2930| {
            if (tx_eip2930.chainId != self.pub_client.chain_id) return error.InvalidChainId;
            if (tx_eip2930.to) |addr| if (!try utils.isAddress(self.alloc, addr)) return error.InvalidAddress;
        },
        .legacy => |tx_legacy| {
            if (tx_legacy.chainId != 0 and tx_legacy.chainId != self.pub_client.chain_id) return error.InvalidChainId;
            if (tx_legacy.to) |addr| if (!try utils.isAddress(self.alloc, addr)) return error.InvalidAddress;
        },
    }
}

pub fn sendSignedTransaction(self: *Wallet, tx: transaction.TransactionEnvelope) !types.Hex {
    const serialized = try serialize.serializeTransaction(self.alloc, tx, null);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &hash_buffer, .{});

    const signed = try self.signer.sign(hash_buffer);
    const serialized_signed = try serialize.serializeTransaction(self.alloc, tx, signed);

    const hex = try std.fmt.allocPrint(self.alloc, "{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

    return self.pub_client.sendRawTransaction(hex);
}

pub fn sendTransaction(self: *Wallet, unprepared_envelope: transaction.PrepareEnvelope) !types.Hex {
    const prepared = try self.prepareTransaction(unprepared_envelope);

    try self.assertTransaction(prepared);

    return try self.sendSignedTransaction(prepared);
}

test "Address match" {
    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .anvil);
    defer wallet.deinit();

    try testing.expectEqualStrings(try wallet.getWalletAddress(), "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
}

test "verifyMessage" {
    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .anvil);
    defer wallet.deinit();

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0", &hash_buffer, .{});
    const sign = try wallet.signer.sign(hash_buffer);

    try testing.expect(wallet.signer.verifyMessage(sign, hash_buffer));
}

test "signMessage" {
    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .anvil);
    defer wallet.deinit();

    const sig = try wallet.signEthereumMessage(testing.allocator, "hello world");
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("a461f509887bd19e312c0c58467ce8ff8e300d3c1a90b608a760c5b80318eaf15fe57c96f9175d6cd4daad4663763baa7e78836e067d0163e9a2ccf2ff753f5b00", hex);
}

test "sendTransaction" {
    // CI coverage runner dislikes this tests so for now we skip it.
    if (true) return error.SkipZigTest;
    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .ethereum);
    defer wallet.deinit();

    var tx: transaction.PrepareEnvelope = .{ .eip1559 = undefined };
    tx.eip1559.type = 2;
    tx.eip1559.value = try utils.parseEth(1);
    tx.eip1559.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

    const tx_hash = try wallet.sendTransaction(tx);

    try testing.expect(tx_hash.len != 0);
}

test "assertTransaction" {
    var tx: transaction.TransactionEnvelope = undefined;

    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .ethereum);
    defer wallet.deinit();

    tx = .{ .eip1559 = .{
        .nonce = 0,
        .gas = 21001,
        .maxPriorityFeePerGas = 2,
        .maxFeePerGas = 2,
        .chainId = 1,
        .accessList = &.{},
        .value = 0,
        .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.eip1559.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.eip1559.chainId = 1;
    tx.eip1559.to = "";
    try testing.expectError(error.InvalidAddress, wallet.assertTransaction(tx));

    tx.eip1559.maxPriorityFeePerGas = 69;
    tx.eip1559.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
    try testing.expectError(error.TransactionTipToHigh, wallet.assertTransaction(tx));
}

test "assertTransactionLegacy" {
    var tx: transaction.TransactionEnvelope = undefined;

    var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .ethereum);
    defer wallet.deinit();

    tx = .{ .eip2930 = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .accessList = &.{},
        .value = 0,
        .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.eip2930.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.eip2930.chainId = 1;
    tx.eip2930.to = "";
    try testing.expectError(error.InvalidAddress, wallet.assertTransaction(tx));

    tx = .{ .legacy = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .value = 0,
        .to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.legacy.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.legacy.chainId = 1;
    tx.legacy.to = "";
    try testing.expectError(error.InvalidAddress, wallet.assertTransaction(tx));
}
