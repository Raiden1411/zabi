const eip712 = @import("abi/eip712.zig");
const secp256k1 = @import("secp256k1");
const serialize = @import("encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");

// Types
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @import("tests/Anvil.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const Chains = types.PublicChains;
const LondonEthCall = transaction.LondonEthCall;
const LegacyEthCall = transaction.LegacyEthCall;
const Hex = types.Hex;
const Hash = types.Hash;
const InitOptsHttp = PubClient.InitOptions;
const InitOptsWs = WebSocketClient.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const PubClient = @import("Client.zig");
const Signer = secp256k1.Signer;
const Signature = secp256k1.Signature;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionReceipt = transaction.TransactionReceipt;
const TypedDataDomain = eip712.TypedDataDomain;
const UnpreparedTransactionEnvelope = transaction.UnpreparedTransactionEnvelope;
const WebSocketClient = @import("WebSocket.zig");

/// The type of client used by the wallet instance.
pub const WalletClients = enum { http, websocket };

/// Creates a wallet instance based on which type of client defined in
/// `WalletClients`. Depending on the type of client the underlaying methods
/// of `pub_client` can be changed. The http and websocket client do not
/// mirror 100% in terms of their methods.
///
/// The client's methods can all be accessed under `pub_client`.
/// The same goes for the signer and libsecp256k1.
pub fn Wallet(comptime client_type: WalletClients) type {
    return struct {
        /// Allocator used by the wallet implementation
        allocator: Allocator,
        /// Arena used to manage allocated memory
        arena: *ArenaAllocator,
        /// Http client used to make request. Supports almost all rpc methods.
        pub_client: if (client_type == .http) *PubClient else *WebSocketClient,
        /// Signer that will sign transactions or ethereum messages.
        /// Its based on libsecp256k1.
        signer: Signer,

        /// Init wallet instance. Must call `deinit` to clean up.
        /// The init opts will depend on the `client_type`.
        pub fn init(private_key: []const u8, opts: if (client_type == .http) InitOptsHttp else InitOptsWs) !*Wallet(client_type) {
            var wallet = try opts.allocator.create(Wallet(client_type));
            errdefer opts.allocator.destroy(wallet);

            wallet.arena = try opts.allocator.create(ArenaAllocator);
            errdefer opts.allocator.destroy(wallet.arena);

            wallet.arena.* = ArenaAllocator.init(opts.allocator);

            const client = client: {
                switch (client_type) {
                    .http => {
                        break :client try PubClient.init(opts);
                    },
                    .websocket => {
                        // We need to create the pointer so that we can init the client
                        const ws_client = try opts.allocator.create(WebSocketClient);
                        errdefer opts.allocator.destroy(ws_client);

                        try ws_client.init(opts);

                        break :client ws_client;
                    },
                }
            };
            const signer = try Signer.init(private_key);

            wallet.pub_client = client;
            wallet.allocator = wallet.arena.allocator();
            wallet.signer = signer;

            return wallet;
        }
        /// Inits wallet from a random generated priv key. Must call `deinit` after.
        /// The init opts will depend on the `client_type`.
        pub fn initFromRandomKey(opts: if (client_type == .http) InitOptsHttp else InitOptsWs) !*Wallet(client_type) {
            var wallet = try opts.allocator.create(Wallet(client_type));
            errdefer opts.allocator.destroy(wallet);

            wallet.arena = try opts.allocator.create(ArenaAllocator);
            errdefer opts.allocator.destroy(wallet.arena);

            wallet.arena.* = ArenaAllocator.init(opts.allocator);

            const client = client: {
                switch (client_type) {
                    .http => {
                        break :client try PubClient.init(opts);
                    },
                    .websocket => {
                        // We need to create the pointer so that we can init the client
                        const ws_client = try opts.allocator.create(WebSocketClient);
                        errdefer opts.allocator.destroy(ws_client);

                        try ws_client.init(opts);

                        break :client ws_client;
                    },
                }
            };
            const signer = try Signer.generateRandomSigner();

            wallet.pub_client = client;
            wallet.allocator = wallet.arena.allocator();
            wallet.signer = signer;

            return wallet;
        }
        /// Clears the arena and destroys any created pointers
        pub fn deinit(self: *Wallet(client_type)) void {
            self.pub_client.deinit();

            const allocator = self.arena.child_allocator;
            self.signer.deinit();
            self.arena.deinit();
            allocator.destroy(self.arena);
            if (client_type == .websocket) allocator.destroy(self.pub_client);
            allocator.destroy(self);
        }
        /// Signs a ethereum message with the specified prefix.
        /// Uses libsecp256k1 to sign the message. This mirrors geth
        /// The Signatures recoverId doesn't include the chain_id
        pub fn signEthereumMessage(self: *Wallet(client_type), message: []const u8) !Signature {
            return try self.signer.signMessage(self.allocator, message);
        }
        /// Signs a EIP712 message according to the expecification
        /// https://eips.ethereum.org/EIPS/eip-712
        ///
        /// `types` parameter is expected to be a struct where the struct
        /// keys are used to grab the solidity type information so that the
        /// encoding and hashing can happen based on it. See the specification
        /// for more details.
        ///
        /// `primary_type` is the expected main type that you want to hash this message.
        /// Compilation will fail if the provided string doesn't exist on the `types` parameter
        ///
        /// `domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
        /// domain types.
        ///
        /// `message` is expected to be a struct where the solidity types are transalated to the native
        /// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
        /// In the future work will be done where the compiler will offer more clearer types
        /// base on a meta programming type function.
        ///
        /// Returns the libsecp256k1 signature type.
        pub fn signTypedData(self: *Wallet(client_type), comptime eip_types: anytype, comptime primary_type: []const u8, domain: ?TypedDataDomain, message: anytype) !Signature {
            return try self.signer.sign(try eip712.hashTypedData(self.allocator, eip_types, primary_type, domain, message));
        }
        /// Get the wallet address.
        /// Uses the wallet public key to generate the address.
        /// This will allocate and the returned address is already checksumed
        pub fn getWalletAddress(self: *Wallet(client_type)) !Address {
            return self.signer.getAddressFromPublicKey();
        }
        /// Verifies if a given signature was signed by the current wallet.
        /// Uses libsecp256k1 to enable this.
        pub fn verifyMessage(self: *Wallet(client_type), sig: Signature, message: []const u8) !bool {
            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(message, &hash_buffer, .{});
            return try self.signer.verifyMessage(sig, hash_buffer);
        }
        /// Verifies a EIP712 message according to the expecification
        /// https://eips.ethereum.org/EIPS/eip-712
        ///
        /// `types` parameter is expected to be a struct where the struct
        /// keys are used to grab the solidity type information so that the
        /// encoding and hashing can happen based on it. See the specification
        /// for more details.
        ///
        /// `primary_type` is the expected main type that you want to hash this message.
        /// Compilation will fail if the provided string doesn't exist on the `types` parameter
        ///
        /// `domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
        /// domain types.
        ///
        /// `message` is expected to be a struct where the solidity types are transalated to the native
        /// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
        /// In the future work will be done where the compiler will offer more clearer types
        /// base on a meta programming type function.
        ///
        /// Returns the libsecp256k1 signature type.
        pub fn verifyTypedData(self: *Wallet(client_type), sig: Signature, comptime eip712_types: anytype, comptime primary_type: []const u8, domain: ?TypedDataDomain, message: anytype) !bool {
            const hash = try eip712.hashTypedData(self.allocator, eip712_types, primary_type, domain, message);

            const address = try secp256k1.recoverEthereumAddress(hash, sig);
            const wallet_address = try self.getWalletAddress();

            return std.mem.eql(u8, &wallet_address, &address);
        }
        /// Prepares a transaction based on it's type so that it can be sent through the network.
        /// Only the null struct properties will get changed.
        /// Everything that gets set before will not be touched.
        pub fn prepareTransaction(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !TransactionEnvelope {
            const address = try self.getWalletAddress();

            switch (unprepared_envelope.type) {
                .cancun => {
                    // zig fmt: off
                    var request: LondonEthCall = .{
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas,
                        .maxFeePerGas = unprepared_envelope.maxFeePerGas,
                        .maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };
                    // zig fmt: on

                    const curr_block = try self.pub_client.getBlockByNumber(.{});
                    const chain_id = unprepared_envelope.chainId orelse self.pub_client.chain_id;
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};
                    const max_fee_per_blob = unprepared_envelope.maxFeePerBlobGas orelse try self.pub_client.estimateBlobMaxFeePerGas();
                    const blob_version = unprepared_envelope.blobVersionedHashes orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

                    if (unprepared_envelope.maxFeePerGas == null or unprepared_envelope.maxPriorityFeePerGas == null) {
                        const fees = try self.pub_client.estimateFeesPerGas(.{ .london = request }, curr_block);
                        request.maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas orelse fees.london.max_priority_fee;
                        request.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;

                        if (unprepared_envelope.maxFeePerGas) |fee| {
                            if (fee < fees.london.max_priority_fee) return error.MaxFeePerGasUnderflow;
                        }
                    }

                    if (unprepared_envelope.gas == null) {
                        request.gas = try self.pub_client.estimateGas(.{ .london = request }, .{});
                    }

                    // zig fmt: off
                    return .{ .cancun = .{
                        .chainId = chain_id,
                        .nonce = nonce,
                        .gas = request.gas.?,
                        .maxFeePerGas = request.maxFeePerGas.?,
                        .maxPriorityFeePerGas = request.maxPriorityFeePerGas.?,
                        .maxFeePerBlobGas = max_fee_per_blob,
                        .to = request.to,
                        .data = request.data,
                        .value = request.value.?,
                        .accessList = accessList,
                        .blobVersionedHashes = blob_version, 
                    }};
                    // zig fmt: on

                },
                .london => {
                    // zig fmt: off
                    var request: LondonEthCall = .{
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas,
                        .maxFeePerGas = unprepared_envelope.maxFeePerGas,
                        .maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };
                    // zig fmt: on

                    const curr_block = try self.pub_client.getBlockByNumber(.{});
                    const chain_id = unprepared_envelope.chainId orelse self.pub_client.chain_id;
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

                    if (unprepared_envelope.maxFeePerGas == null or unprepared_envelope.maxPriorityFeePerGas == null) {
                        const fees = try self.pub_client.estimateFeesPerGas(.{ .london = request }, curr_block);
                        request.maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas orelse fees.london.max_priority_fee;
                        request.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;

                        if (unprepared_envelope.maxFeePerGas) |fee| {
                            if (fee < fees.london.max_priority_fee) return error.MaxFeePerGasUnderflow;
                        }
                    }

                    if (unprepared_envelope.gas == null) {
                        request.gas = try self.pub_client.estimateGas(.{ .london = request }, .{});
                    }

                    // zig fmt: off
                    return .{ .london = .{
                        .chainId = chain_id,
                        .nonce = nonce,
                        .gas = request.gas.?,
                        .maxFeePerGas = request.maxFeePerGas.?,
                        .maxPriorityFeePerGas = request.maxPriorityFeePerGas.?,
                        .to = request.to,
                        .data = request.data,
                        .value = request.value.?,
                        .accessList = accessList,
                    }};
                    // zig fmt: on
                },
                .berlin => {
                    // zig fmt: off
                    var request: LegacyEthCall = .{ 
                        .from = address, 
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas, 
                        .gasPrice = unprepared_envelope.gasPrice, 
                        .data = unprepared_envelope.data, 
                        .value = unprepared_envelope.value orelse 0
                    };
                    // zig fmt: on

                    const curr_block = try self.pub_client.getBlockByNumber(.{});
                    const chain_id = unprepared_envelope.chainId orelse self.pub_client.chain_id;
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

                    if (unprepared_envelope.gasPrice == null) {
                        const fees = try self.pub_client.estimateFeesPerGas(.{ .legacy = request }, curr_block);
                        request.gasPrice = fees.legacy.gas_price;
                    }

                    if (unprepared_envelope.gas == null) {
                        request.gas = try self.pub_client.estimateGas(.{ .legacy = request }, .{});
                    }

                    // zig fmt: off
                    return .{ .berlin = .{
                        .chainId = chain_id,
                        .nonce = nonce,
                        .gas = request.gas.?,
                        .gasPrice = request.gasPrice.?,
                        .to = request.to,
                        .data = request.data,
                        .value = request.value.?,
                        .accessList = accessList,
                    }};
                    // zig fmt: on
                },
                _ => {
                    if (@intFromEnum(unprepared_envelope.type) < @as(u8, @intCast(0xc0)))
                        return error.InvalidTransactionType;

                    // zig fmt: off
                    var request: LegacyEthCall = .{ 
                        .from = address, 
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas, 
                        .gasPrice = unprepared_envelope.gasPrice, 
                        .data = unprepared_envelope.data, 
                        .value = unprepared_envelope.value orelse 0
                    };
                    // zig fmt: on

                    const curr_block = try self.pub_client.getBlockByNumber(.{});
                    const chain_id = unprepared_envelope.chainId orelse self.pub_client.chain_id;

                    const nonce: u64 = unprepared_envelope.nonce orelse try self.pub_client.getAddressTransactionCount(.{ .address = address });

                    if (unprepared_envelope.gasPrice == null) {
                        const fees = try self.pub_client.estimateFeesPerGas(.{ .legacy = request }, curr_block);
                        request.gasPrice = fees.legacy.gas_price;
                    }

                    if (unprepared_envelope.gas == null) {
                        request.gas = try self.pub_client.estimateGas(.{ .legacy = request }, .{});
                    }

                    // zig fmt: off
                    return .{ .legacy = .{
                        .chainId = chain_id,
                        .nonce = nonce,
                        .gas = request.gas.?,
                        .gasPrice = request.gasPrice.?,
                        .to = request.to,
                        .data = request.data,
                        .value = request.value.?,
                    }};
                    // zig fmt: on
                },
            }
        }
        /// Asserts that the transactions is ready to be sent.
        /// Will return errors where the values are not expected
        pub fn assertTransaction(self: *Wallet(client_type), tx: TransactionEnvelope) !void {
            switch (tx) {
                .london => |tx_eip1559| {
                    if (tx_eip1559.chainId != self.pub_client.chain_id) return error.InvalidChainId;
                    if (tx_eip1559.maxPriorityFeePerGas > tx_eip1559.maxFeePerGas) return error.TransactionTipToHigh;
                },
                .cancun => |tx_eip4844| {
                    if (tx_eip4844.chainId != self.pub_client.chain_id) return error.InvalidChainId;
                    if (tx_eip4844.maxPriorityFeePerGas > tx_eip4844.maxFeePerGas) return error.TransactionTipToHigh;
                },
                .berlin => |tx_eip2930| {
                    if (tx_eip2930.chainId != self.pub_client.chain_id) return error.InvalidChainId;
                },
                .legacy => |tx_legacy| {
                    if (tx_legacy.chainId != 0 and tx_legacy.chainId != self.pub_client.chain_id) return error.InvalidChainId;
                },
            }
        }
        /// Signs, serializes and send the transaction via `eth_sendRawTransaction`.
        /// Returns the transaction hash.
        pub fn sendSignedTransaction(self: *Wallet(client_type), tx: TransactionEnvelope) !Hash {
            const serialized = try serialize.serializeTransaction(self.allocator, tx, null);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeTransaction(self.allocator, tx, signed);

            const hex = try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

            return self.pub_client.sendRawTransaction(hex);
        }
        /// Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.
        /// Will return error if the envelope is incorrect
        pub fn sendTransaction(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !Hash {
            const prepared = try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            return self.sendSignedTransaction(prepared);
        }
        /// Waits until the transaction gets mined and we can grab the receipt.
        /// If fail if the retry counter is excedded.
        pub fn waitForTransactionReceipt(self: *Wallet(client_type), tx_hash: Hash, confirmations: u8) !?TransactionReceipt {
            return try self.pub_client.waitForTransactionReceipt(tx_hash, confirmations);
        }
    };
}

test "Address match" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    try testing.expectEqualStrings(&try wallet.getWalletAddress(), &try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"));
}

test "verifyMessage" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0", &hash_buffer, .{});
    const sign = try wallet.signer.sign(hash_buffer);

    try testing.expect(wallet.signer.verifyMessage(sign, hash_buffer));
}

test "signMessage" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const sig = try wallet.signEthereumMessage("hello world");
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("a461f509887bd19e312c0c58467ce8ff8e300d3c1a90b608a760c5b80318eaf15fe57c96f9175d6cd4daad4663763baa7e78836e067d0163e9a2ccf2ff753f5b00", hex);
}

test "signTypedData" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const sig = try wallet.signTypedData(.{ .EIP712Domain = &.{} }, "EIP712Domain", .{}, .{});
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da87197eb020923476a6d0149ca90bc1c894251cc30b38e0dd2cdd48567e12386d3ed40a509397410a4fd2d66e1300a39ac42f828f8a5a2cb948b35c22cf29e801", hex);
}

test "verifyTypedData" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const domain: eip712.TypedDataDomain = .{ .name = "Ether Mail", .version = "1", .chainId = 1, .verifyingContract = "0x0000000000000000000000000000000000000000" };
    const e_types = .{ .EIP712Domain = &.{ .{ .type = "string", .name = "name" }, .{ .name = "version", .type = "string" }, .{ .name = "chainId", .type = "uint256" }, .{ .name = "verifyingContract", .type = "address" } }, .Person = &.{ .{ .name = "name", .type = "string" }, .{ .name = "wallet", .type = "address" } }, .Mail = &.{ .{ .name = "from", .type = "Person" }, .{ .name = "to", .type = "Person" }, .{ .name = "contents", .type = "string" } } };

    const sig = try Signature.fromHex("0x32f3d5975ba38d6c2fba9b95d5cbed1febaa68003d3d588d51f2de522ad54117760cfc249470a75232552e43991f53953a3d74edf6944553c6bef2469bb9e5921b");
    const validate = try wallet.verifyTypedData(sig, e_types, "Mail", domain, .{ .from = .{ .name = "Cow", .wallet = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" }, .to = .{ .name = "Bob", .wallet = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" }, .contents = "Hello, Bob!" });

    try testing.expect(validate);
}

test "sendTransaction" {
    // CI coverage runner dislikes this tests so for now we skip it.
    if (true) return error.SkipZigTest;
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const tx: UnpreparedTransactionEnvelope = .{ .type = .london, .value = try utils.parseEth(1), .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8") };

    const tx_hash = try wallet.sendTransaction(tx);
    const receipt = try wallet.waitForTransactionReceipt(tx_hash, 1);

    try testing.expect(tx_hash.len != 0);
    try testing.expect(receipt != null);
}

test "assertTransaction" {
    var tx: TransactionEnvelope = undefined;

    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    tx = .{ .london = .{
        .nonce = 0,
        .gas = 21001,
        .maxPriorityFeePerGas = 2,
        .maxFeePerGas = 2,
        .chainId = 1,
        .accessList = &.{},
        .value = 0,
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.london.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.london.chainId = 1;

    tx.london.maxPriorityFeePerGas = 69;
    tx.london.to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
    try testing.expectError(error.TransactionTipToHigh, wallet.assertTransaction(tx));
}

test "assertTransactionLegacy" {
    var tx: TransactionEnvelope = undefined;

    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet = try Wallet(.http).init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    tx = .{ .berlin = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .accessList = &.{},
        .value = 0,
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.berlin.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.berlin.chainId = 1;

    tx = .{ .legacy = .{
        .nonce = 0,
        .gas = 21001,
        .gasPrice = 2,
        .chainId = 1,
        .value = 0,
        .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"),
        .data = null,
    } };
    try wallet.assertTransaction(tx);

    tx.legacy.chainId = 2;
    try testing.expectError(error.InvalidChainId, wallet.assertTransaction(tx));

    tx.legacy.chainId = 1;
}
