const ckzg4844 = @import("c-kzg-4844");
const eip712 = @import("../abi/eip712.zig");
const secp256k1 = @import("secp256k1");
const serialize = @import("../encoding/serialize.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");
const utils = @import("../utils/utils.zig");

// Types
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Anvil = @import("../tests/Anvil.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const Blob = ckzg4844.KZG4844.Blob;
const Chains = types.PublicChains;
const KZG4844 = ckzg4844.KZG4844;
const LondonEthCall = transaction.LondonEthCall;
const LegacyEthCall = transaction.LegacyEthCall;
const Hex = types.Hex;
const Hash = types.Hash;
const InitOptsHttp = PubClient.InitOptions;
const InitOptsWs = WebSocketClient.InitOptions;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Mutex = std.Thread.Mutex;
const PubClient = @import("Client.zig");
const Sidecar = ckzg4844.KZG4844.Sidecar;
const Signer = secp256k1.Signer;
const Signature = secp256k1.Signature;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionReceipt = transaction.TransactionReceipt;
const TypedDataDomain = eip712.TypedDataDomain;
const UnpreparedTransactionEnvelope = transaction.UnpreparedTransactionEnvelope;
const WebSocketClient = @import("WebSocket.zig");

/// The type of client used by the wallet instance.
pub const WalletClients = enum { http, websocket };

pub const TransactionEnvelopePool = struct {
    mutex: Mutex = .{},
    pooled_envelopes: TransactionEnvelopeQueue,

    pub const Node = TransactionEnvelopeQueue.Node;

    const SearchCriteria = transaction.TransactionTypes;
    const TransactionEnvelopeQueue = std.DoublyLinkedList(TransactionEnvelope);

    /// Finds a transaction envelope from the pool based on the
    /// transaction type. This is thread safe.
    /// Returns null if no transaction was found
    pub fn findTransactionEnvelope(pool: *TransactionEnvelopePool, search: SearchCriteria) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        var last_tx_node = pool.pooled_envelopes.last;

        while (last_tx_node) |tx_node| : (last_tx_node = tx_node.prev) {
            if (!std.mem.eql(u8, @tagName(tx_node.data), @tagName(search))) continue;

            pool.unsafeReleaseEnvelopeFromPool(tx_node);
            return tx_node.data;
        }

        return null;
    }
    /// Adds a new node into the pool. This is thread safe.
    pub fn addEnvelopeToPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.append(node);
    }
    /// Removes a node from the pool. This is not thread safe.
    pub fn unsafeReleaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.pooled_envelopes.remove(node);
    }
    /// Removes a node from the pool. This is thread safe.
    pub fn releaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.remove(node);
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getFirstElementFromPool(pool: *TransactionEnvelopePool) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        return if (pool.pooled_envelopes.popFirst()) |node| node.data else null;
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getLastElementFromPool(pool: *TransactionEnvelopePool) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        return if (pool.pooled_envelopes.pop()) |node| node.data else null;
    }
    /// Destroys all created pointer. All future operations will deadlock.
    /// This is thread safe.
    pub fn deinit(pool: *TransactionEnvelopePool, allocator: Allocator) void {
        pool.mutex.lock();

        var first = pool.pooled_envelopes.first;
        while (first) |node| {
            defer allocator.destroy(node);
            first = node.next;
        }

        pool.* = undefined;
    }
};

/// Creates a wallet instance based on which type of client defined in
/// `WalletClients`. Depending on the type of client the underlaying methods
/// of `pub_client` can be changed. The http and websocket client do not
/// mirror 100% in terms of their methods.
///
/// The client's methods can all be accessed under `pub_client`.
/// The same goes for the signer and libsecp256k1.
pub fn Wallet(comptime client_type: WalletClients) type {
    return struct {
        /// The wallet underlaying rpc client type (ws or http)
        const ClientType = switch (client_type) {
            .http => PubClient,
            .websocket => WebSocketClient,
        };

        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
        };

        /// Allocator used by the wallet implementation
        allocator: Allocator,
        /// Arena used to manage allocated memory
        arena: *ArenaAllocator,
        /// Pool to store all prepated transaction envelopes.
        /// This is thread safe.
        envelopes_pool: *TransactionEnvelopePool,
        /// Http client used to make request. Supports almost all rpc methods.
        pub_client: *ClientType,
        /// Signer that will sign transactions or ethereum messages.
        /// Its based on libsecp256k1.
        signer: Signer,
        /// The wallet nonce that will be used to send transactions
        wallet_nonce: u64 = 0,

        /// Init wallet instance. Must call `deinit` to clean up.
        /// The init opts will depend on the `client_type`.
        pub fn init(self: *Wallet(client_type), private_key: []const u8, opts: InitOpts) !void {
            const arena = try opts.allocator.create(ArenaAllocator);
            errdefer opts.allocator.destroy(arena);

            const envelopes_pool = try opts.allocator.create(TransactionEnvelopePool);
            errdefer opts.allocator.destroy(envelopes_pool);

            const signer = try Signer.init(private_key);
            const client = client: {
                // We need to create the pointer so that we can init the client
                const client = try opts.allocator.create(ClientType);
                errdefer opts.allocator.destroy(client);

                try client.init(opts);

                break :client client;
            };

            self.* = .{ .allocator = undefined, .pub_client = client, .arena = arena, .signer = signer, .envelopes_pool = envelopes_pool };
            self.arena.* = ArenaAllocator.init(opts.allocator);
            self.envelopes_pool.* = .{ .pooled_envelopes = .{} };
            self.allocator = self.arena.allocator();
            self.wallet_nonce = try self.pub_client.getAddressTransactionCount(.{ .address = try self.signer.getAddressFromPublicKey() });
        }
        /// Inits wallet from a random generated priv key. Must call `deinit` after.
        /// The init opts will depend on the `client_type`.
        pub fn initFromRandomKey(self: *Wallet(client_type), opts: InitOpts) !void {
            const arena = try opts.allocator.create(ArenaAllocator);
            errdefer opts.allocator.destroy(arena);

            const envelopes_pool = try opts.allocator.create(TransactionEnvelopePool);
            errdefer opts.allocator.destroy(envelopes_pool);

            const signer = try Signer.generateRandomSigner();
            const client = client: {
                // We need to create the pointer so that we can init the client
                const client = try opts.allocator.create(ClientType);
                errdefer opts.allocator.destroy(client);

                try client.init(opts);

                break :client client;
            };

            self.* = .{ .allocator = undefined, .pub_client = client, .arena = arena, .signer = signer, .envelopes_pool = envelopes_pool };
            self.arena.* = ArenaAllocator.init(opts.allocator);
            self.envelopes_pool.* = .{ .pooled_envelopes = .{} };
            self.allocator = self.arena.allocator();
        }
        /// Clears the arena and destroys any created pointers
        pub fn deinit(self: *Wallet(client_type)) void {
            self.envelopes_pool.deinit(self.arena.allocator());
            self.pub_client.deinit();
            self.signer.deinit();
            self.arena.deinit();

            const allocator = self.arena.child_allocator;
            allocator.destroy(self.arena);
            allocator.destroy(self.envelopes_pool);
            allocator.destroy(self.pub_client);

            self.* = undefined;
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

            const address = try Signer.recoverEthereumAddress(hash, sig);
            const wallet_address = try self.getWalletAddress();

            return std.mem.eql(u8, &wallet_address, &address);
        }
        /// Find a specific prepared envelope from the pool based on the given search criteria.
        pub fn findTransactionEnvelopeFromPool(self: *Wallet(client_type), search: TransactionEnvelopePool.SearchCriteria) ?TransactionEnvelope {
            return self.envelopes_pool.findTransactionEnvelope(search);
        }
        /// Converts unprepared transaction envelopes and stores them in a pool.
        pub fn poolTransactionEnvelope(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !void {
            const envelope = try self.allocator.create(TransactionEnvelopePool.Node);
            errdefer self.allocator.destroy(envelope);
            envelope.* = .{ .data = undefined };

            envelope.data = try self.prepareTransaction(unprepared_envelope);
            self.envelopes_pool.addEnvelopeToPool(envelope);
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
                        .from = address,
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

                    const nonce: u64 = unprepared_envelope.nonce orelse self.wallet_nonce;

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
                        .from = address,
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

                    const nonce: u64 = unprepared_envelope.nonce orelse self.wallet_nonce;

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

                    const nonce: u64 = unprepared_envelope.nonce orelse self.wallet_nonce;

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
                .legacy => {
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

                    const nonce: u64 = unprepared_envelope.nonce orelse self.wallet_nonce;

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
        ///
        /// Call `waitForTransactionReceipt` to update the wallet nonce or update it manually
        pub fn sendSignedTransaction(self: *Wallet(client_type), tx: TransactionEnvelope) !Hash {
            const serialized = try serialize.serializeTransaction(self.allocator, tx, null);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeTransaction(self.allocator, tx, signed);

            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

            return self.pub_client.sendRawTransaction(hex);
        }
        /// Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.
        /// If any envelope is in the envelope pool it will use that instead in a LIFO order
        /// Will return an error if the envelope is incorrect
        ///
        /// Call `waitForTransactionReceipt` to update the wallet nonce or update it manually
        pub fn sendTransaction(self: *Wallet(client_type), unprepared_envelope: UnpreparedTransactionEnvelope) !Hash {
            const prepared = self.envelopes_pool.getLastElementFromPool() orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            const hash = try self.sendSignedTransaction(prepared);

            return hash;
        }
        /// Sends blob transaction to the network
        /// Trusted setup must be loaded otherwise this will fail.
        pub fn sendBlobTransaction(self: *Wallet(client_type), blobs: []const Blob, unprepared_envelope: UnpreparedTransactionEnvelope, trusted_setup: *KZG4844) !Hash {
            if (unprepared_envelope.type != .cancun)
                return error.InvalidTransactionType;

            if (!trusted_setup.loaded)
                return error.TrustedSetupNotLoaded;

            const prepared = self.envelopes_pool.getLastElementFromPool() orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            const serialized = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, null, blobs, trusted_setup);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, signed, blobs, trusted_setup);

            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

            return self.pub_client.sendRawTransaction(hex);
        }
        /// Sends blob transaction to the network
        /// This uses and already prepared sidecar.
        pub fn sendSidecarTransaction(self: *Wallet(client_type), sidecars: []const Sidecar, unprepared_envelope: UnpreparedTransactionEnvelope) !Hash {
            if (unprepared_envelope.type != .cancun)
                return error.InvalidTransactionType;

            const prepared = self.envelopes_pool.getLastElementFromPool() orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            const serialized = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, null, sidecars);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, signed, sidecars);

            const hex = try std.fmt.allocPrint(self.allocator, "0x{s}", .{std.fmt.fmtSliceHexLower(serialized_signed)});

            return self.pub_client.sendRawTransaction(hex);
        }
        /// Waits until the transaction gets mined and we can grab the receipt.
        /// If fail if the retry counter is excedded.
        ///
        /// Nonce will only get updated if it's able to fetch the receipt.
        /// Use the pub_client waitForTransactionReceipt if you don't want to update the wallet's nonce.
        pub fn waitForTransactionReceipt(self: *Wallet(client_type), tx_hash: Hash, confirmations: u8) !?TransactionReceipt {
            const receipt = try self.pub_client.waitForTransactionReceipt(tx_hash, confirmations);

            // Updates the wallet nonce to be ready for the next transaction.
            self.wallet_nonce += 1;

            return receipt;
        }
    };
}

test "Address match" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    try testing.expectEqualStrings(&try wallet.getWalletAddress(), &try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"));
}

test "verifyMessage" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash("02f1827a6980847735940084773594008252099470997970c51812dc3a010c7d01b50e0d17dc79c8880de0b6b3a764000080c0", &hash_buffer, .{});
    const sign = try wallet.signer.sign(hash_buffer);

    try testing.expect(wallet.signer.verifyMessage(sign, hash_buffer));
}

test "signMessage" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const sig = try wallet.signEthereumMessage("hello world");
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("a461f509887bd19e312c0c58467ce8ff8e300d3c1a90b608a760c5b80318eaf15fe57c96f9175d6cd4daad4663763baa7e78836e067d0163e9a2ccf2ff753f5b00", hex);
}

test "signTypedData" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const sig = try wallet.signTypedData(.{ .EIP712Domain = &.{} }, "EIP712Domain", .{}, .{});
    const hex = try sig.toHex(testing.allocator);
    defer testing.allocator.free(hex);

    try testing.expectEqualStrings("da87197eb020923476a6d0149ca90bc1c894251cc30b38e0dd2cdd48567e12386d3ed40a509397410a4fd2d66e1300a39ac42f828f8a5a2cb948b35c22cf29e801", hex);
}

test "verifyTypedData" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
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
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    const tx: UnpreparedTransactionEnvelope = .{ .type = .london, .value = try utils.parseEth(1), .to = try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8") };

    const tx_hash = try wallet.sendTransaction(tx);
    const receipt = try wallet.waitForTransactionReceipt(tx_hash, 1);

    try testing.expect(tx_hash.len != 0);
    try testing.expect(receipt != null);
}

test "Pool transactions" {
    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
    defer wallet.deinit();

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try wallet.poolTransactionEnvelope(.{ .type = .london });
    }

    const env = wallet.findTransactionEnvelopeFromPool(.london);
    try testing.expect(env != null);
}

test "assertTransaction" {
    var tx: TransactionEnvelope = undefined;

    const uri = try std.Uri.parse("http://localhost:8545/");
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
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
    var wallet: Wallet(.http) = undefined;
    try wallet.init("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", .{ .allocator = testing.allocator, .uri = uri });
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
