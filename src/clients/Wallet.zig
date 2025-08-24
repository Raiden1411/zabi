//! Creates a wallet instance based on which type of client defined in `WalletClients`.
//!
//! Depending on the type of client the underlaying methods of `rpc_client` can be changed.
//! The http and websocket client do not mirror 100% in terms of their methods.
//!
//! The client's methods can all be accessed under `rpc_client`. The same goes for the signer.
const abitype = @import("zabi-abi").abitypes;
const abi_op = @import("optimism/abi_optimism.zig");
const ckzg4844 = @import("c_kzg_4844");
const constants = zabi_utils.constants;
const decoder = @import("zabi-decoding").abi_decoder;
const eip712 = @import("zabi-abi").eip712;
const encoder = zabi_encoding.abi_encoding;
const logs = zabi_types.log;
const meta = @import("zabi-meta").abi;
const op_types = @import("optimism/types/types.zig");
const op_utils = @import("optimism/utils.zig");
const serialize = zabi_encoding.serialize;
const std = @import("std");
const testing = std.testing;
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const utils = zabi_utils.utils;
const zabi_encoding = @import("zabi-encoding");
const zabi_crypto = @import("zabi-crypto");
const zabi_types = @import("zabi-types");
const zabi_utils = @import("zabi-utils");
const withdrawal_types = @import("optimism/types/withdrawl.zig");

// Types
const AbiDecoded = decoder.AbiDecoded;
const AbiEncoder = encoder.AbiEncoder;
const AbiParametersToPrimative = meta.AbiParametersToPrimative;
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const AuthorizationPayload = transaction.AuthorizationPayload;
const BerlinTransactionEnvelope = transaction.BerlinTransactionEnvelope;
const Blob = ckzg4844.KZG4844.Blob;
const CancunSerializeErrors = serialize.CancunSerializeErrors;
const CancunTransactionEnvelope = transaction.CancunTransactionEnvelope;
const Chains = types.PublicChains;
const Constructor = abitype.Constructor;
const DepositData = transaction.DepositData;
const DepositEnvelope = transaction.DepositTransactionEnvelope;
const EthCall = transaction.EthCall;
const EIP712Errors = eip712.EIP712Errors;
const Eip7702TransactionEnvelope = transaction.Eip7702TransactionEnvelope;
const Function = abitype.Function;
const KZG4844 = ckzg4844.KZG4844;
const Hash = types.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const LegacyTransactionEnvelope = transaction.LegacyTransactionEnvelope;
const LondonEthCall = transaction.LondonEthCall;
const LondonTransactionEnvelope = transaction.LondonTransactionEnvelope;
const L2Output = op_types.L2Output;
const Mutex = std.Thread.Mutex;
const PreparedWithdrawal = withdrawal_types.PreparedWithdrawal;
const Provider = @import("Provider.zig");
const RootProof = withdrawal_types.WithdrawalRootProof;
const RPCResponse = types.RPCResponse;
const SerializeErrors = serialize.SerializeErrors;
const Sidecar = ckzg4844.KZG4844.Sidecar;
const Signer = zabi_crypto.Signer;
const Signature = zabi_crypto.signature.Signature;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionReceipt = transaction.TransactionReceipt;
const TransactionTypes = transaction.TransactionTypes;
const TypedDataDomain = eip712.TypedDataDomain;
const UnpreparedTransactionEnvelope = transaction.UnpreparedTransactionEnvelope;
const Withdrawal = withdrawal_types.Withdrawal;
const WithdrawalEnvelope = withdrawal_types.WithdrawalEnvelope;
const WithdrawalNoHash = withdrawal_types.WithdrawalNoHash;
const WithdrawalRequest = withdrawal_types.WithdrawalRequest;

/// Pool of prepared transaciton envelopes.
pub const TransactionEnvelopePool = struct {
    mutex: Mutex = .{},
    /// DoublyLinkedList queue. Iterate from last to first (LIFO)
    pooled_envelopes: std.DoublyLinkedList,

    /// LinkedList node.
    pub const Node = struct {
        data: TransactionEnvelope,
        /// Entry in `ConnectionPool.used` or `ConnectionPool.free`.
        pool_node: std.DoublyLinkedList.Node,
    };

    /// Search criteria used to find the required parameter.
    const SearchCriteria = struct {
        type: TransactionTypes,
        nonce: u64,
    };

    /// Finds a transaction envelope from the pool based on the
    /// transaction type and it's nonce in case there are transactions with the same type. This is thread safe.
    ///
    /// Returns null if no transaction was found
    pub fn findTransactionEnvelope(
        pool: *TransactionEnvelopePool,
        allocator: Allocator,
        search: SearchCriteria,
    ) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        var last_tx_node = pool.pooled_envelopes.last;

        while (last_tx_node) |tx_node| : (last_tx_node = tx_node.prev) {
            const data: *Node = @alignCast(@fieldParentPtr("pool_node", tx_node));
            switch (data.data) {
                inline else => |pooled_tx| if (pooled_tx.nonce != search.nonce)
                    continue,
            }

            if (!std.mem.eql(u8, @tagName(data.data), @tagName(search.type)))
                continue;

            defer allocator.destroy(data);

            pool.unsafeReleaseEnvelopeFromPool(data);
            return data.data;
        }

        return null;
    }
    /// Adds a new node into the pool. This is thread safe.
    pub fn addEnvelopeToPool(
        pool: *TransactionEnvelopePool,
        node: *Node,
    ) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.append(&node.pool_node);
    }
    /// Removes a node from the pool. This is not thread safe.
    pub fn unsafeReleaseEnvelopeFromPool(
        pool: *TransactionEnvelopePool,
        node: *Node,
    ) void {
        pool.pooled_envelopes.remove(&node.pool_node);
    }
    /// Removes a node from the pool. This is thread safe.
    pub fn releaseEnvelopeFromPool(
        pool: *TransactionEnvelopePool,
        node: *Node,
    ) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.remove(&node.pool_node);
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getFirstElementFromPool(
        pool: *TransactionEnvelopePool,
        allocator: Allocator,
    ) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        if (pool.pooled_envelopes.popFirst()) |node| {
            const data: *Node = @alignCast(@fieldParentPtr("pool_node", node));
            defer allocator.destroy(data);

            return data.data;
        } else return null;
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getLastElementFromPool(
        pool: *TransactionEnvelopePool,
        allocator: Allocator,
    ) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        if (pool.pooled_envelopes.pop()) |node| {
            const data: *Node = @alignCast(@fieldParentPtr("pool_node", node));
            defer allocator.destroy(data);

            return data.data;
        } else return null;
    }
    /// Destroys all created pointer. All future operations will deadlock.
    /// This is thread safe.
    pub fn deinit(
        pool: *TransactionEnvelopePool,
        allocator: Allocator,
    ) void {
        pool.mutex.lock();

        var first = pool.pooled_envelopes.first;
        while (first) |node| {
            const data: *Node = @alignCast(@fieldParentPtr("pool_node", node));
            defer allocator.destroy(data);
            first = node.next;
        }

        pool.* = undefined;
    }
};

const Wallet = @This();

/// Nonce manager that use's the rpc client as the source of truth
/// for checking internally that the cached and managed values can be used.
pub const NonceManager = struct {
    /// The address that will get it's nonce managed.
    address: Address,
    /// The current nonce in use.
    managed: u64,
    /// The cached nonce.
    cache: u64,

    const Self = @This();

    /// Sets the initial state of the `NonceManager`.
    pub fn initManager(address: Address) NonceManager {
        return .{
            .address = address,
            .managed = 0,
            .cache = 0,
        };
    }
    /// Gets the nonce from either the cache or from the network.
    ///
    /// Resets the `manager` nonce value and the `cache` if the nonce value from the network
    /// is higher than one from the `cache`.
    pub fn getNonce(
        self: *Self,
        rpc_client: *Provider,
    ) !u64 {
        const nonce: u64 = nonce: {
            const nonce = try rpc_client.getAddressTransactionCount(.{
                .address = self.address,
                .tag = .pending,
            });
            defer nonce.deinit();

            const cached_nonce = self.cache;
            defer self.resetNonce();

            if (cached_nonce > 0 and nonce.response <= cached_nonce)
                break :nonce cached_nonce + 1;

            self.cache = 0;
            break :nonce nonce.response;
        };

        const nonce_from_manager = self.managed;

        return nonce + nonce_from_manager;
    }
    /// Increments the `manager` by one.
    pub fn incrementNonce(self: *Self) void {
        self.managed += 1;
    }
    /// Gets the nonce from either the cache or from the network and updates internally.
    ///
    /// Resets the `manager` nonce value and the `cache` if the nonce value from the network
    /// is higher than one from the `cache`.
    pub fn updateNonce(
        self: *Self,
        rpc_client: *Provider,
    ) !u64 {
        self.incrementNonce();
        const nonce: u64 = nonce: {
            const nonce = try rpc_client.getAddressTransactionCount(.{
                .address = self.address,
                .tag = .pending,
            });
            defer nonce.deinit();

            const cached_nonce = self.cache;
            defer self.resetNonce();

            if (cached_nonce > 0 and nonce.response <= cached_nonce)
                break :nonce cached_nonce + 1;

            self.cache = 0;
            break :nonce nonce.response;
        };

        self.cache = nonce;

        return nonce;
    }
    /// Resets the `manager` to 0.
    pub fn resetNonce(self: *Self) void {
        self.managed = 0;
    }
};

/// Allocator used by the wallet implementation
allocator: Allocator,
/// Pool to store all prepated transaction envelopes.
///
/// This is thread safe.
envelopes_pool: TransactionEnvelopePool,
/// Internal nonce manager.
///
/// Set it null to just use the network to update nonce values.
nonce_manager: ?NonceManager,
/// JSON-RPC client used to make request. Supports almost all `eth_` rpc methods.
rpc_client: *Provider,
/// Signer that will sign transactions or ethereum messages.
///
/// Its based on a custom implementation meshed with zig's source code.
signer: Signer,

/// Sets the wallet initial state.
///
/// The init opts will depend on the [client_type](/api/clients/wallet#walletclients).
///
/// Also adds the hability to use a nonce manager or to use the network directly.
pub fn init(
    private_key: ?Hash,
    allocator: Allocator,
    provider: *Provider,
    nonce_manager: bool,
) !Wallet {
    const signer = try Signer.init(private_key);

    return .{
        .allocator = allocator,
        .rpc_client = provider,
        .signer = signer,
        .envelopes_pool = .{
            .pooled_envelopes = .{},
        },
        .nonce_manager = if (nonce_manager) NonceManager.initManager(signer.address_bytes) else null,
    };
}

/// Clears memory and destroys any created pointers
pub fn deinit(self: *Wallet) void {
    self.envelopes_pool.deinit(self.allocator);
}

/// Asserts that the transactions is ready to be sent.
/// Will return errors where the values are not expected
pub fn assertTransaction(
    self: *Wallet,
    tx: TransactionEnvelope,
) !void {
    switch (tx) {
        .london => |tx_eip1559| {
            if (tx_eip1559.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
            if (tx_eip1559.maxPriorityFeePerGas > tx_eip1559.maxFeePerGas) return error.TransactionTipToHigh;
        },
        .eip7702 => |tx_eip7702| {
            if (tx_eip7702.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
            if (tx_eip7702.maxPriorityFeePerGas > tx_eip7702.maxFeePerGas) return error.TransactionTipToHigh;
        },
        .cancun => |tx_eip4844| {
            if (tx_eip4844.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
            if (tx_eip4844.maxPriorityFeePerGas > tx_eip4844.maxFeePerGas) return error.TransactionTipToHigh;

            if (tx_eip4844.blobVersionedHashes) |blob_hashes| {
                if (blob_hashes.len == 0)
                    return error.EmptyBlobs;

                if (blob_hashes.len > constants.MAX_BLOB_NUMBER_PER_BLOCK)
                    return error.TooManyBlobs;

                for (blob_hashes) |hashes|
                    if (hashes[0] != constants.VERSIONED_HASH_VERSION_KZG)
                        return error.BlobVersionNotSupported;
            }

            if (tx_eip4844.to == null)
                return error.CreateBlobTransaction;
        },
        .berlin => |tx_eip2930| if (tx_eip2930.chainId != @intFromEnum(self.rpc_client.network_config.chain_id))
            return error.InvalidChainId,
        .legacy => |tx_legacy| if (tx_legacy.chainId != 0 and tx_legacy.chainId != @intFromEnum(self.rpc_client.network_config.chain_id))
            return error.InvalidChainId,
    }
}

/// Creates a contract on the network.
/// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
pub fn deployContract(
    wallet: *Wallet,
    constructor: Constructor,
    constructor_args: anytype,
    bytecode: []u8,
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    var copy = overrides;

    if (copy.to != null)
        return error.CreatingContractToKnowAddress;

    const value = copy.value orelse 0;
    switch (constructor.stateMutability) {
        .nonpayable => if (value != 0)
            return error.ValueInNonPayableConstructor,
        .payable => {},
    }

    const encoded = try constructor.encodeFromReflection(wallet.allocator, constructor_args);
    defer wallet.allocator.free(encoded);

    copy.data = try std.mem.concat(wallet.allocator, u8, &.{ bytecode, encoded });
    defer wallet.allocator.free(copy.data.?);

    return wallet.sendTransaction(copy);
}

/// Creates a contract on the network.
/// If the constructor abi contains inputs it will encode `constructor_args` accordingly.
pub fn deployContractComptime(
    wallet: *Wallet,
    comptime constructor: Constructor,
    args: AbiParametersToPrimative(constructor.inputs),
    bytecode: []u8,
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    var copy = overrides;

    if (copy.to != null)
        return error.CreatingContractToKnowAddress;

    const value = copy.value orelse 0;
    switch (constructor.stateMutability) {
        .nonpayable => if (value != 0)
            return error.ValueInNonPayableConstructor,
        .payable => {},
    }

    const encoded = try constructor.encode(wallet.allocator, args);
    defer wallet.allocator.free(encoded);

    copy.data = try std.mem.concat(wallet.allocator, u8, &.{ bytecode, encoded });
    defer wallet.allocator.free(copy.data.?);

    return wallet.sendTransaction(copy);
}

/// Invokes the contract method to `depositTransaction`. This will send
/// a transaction to the network.
pub fn depositTransaction(
    self: *Wallet,
    deposit_envelope: DepositEnvelope,
) !RPCResponse(Hash) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const address = self.signer.address_bytes;
    const deposit_data = try self.prepareDepositTransaction(deposit_envelope);

    const data = try abi_op.deposit_transaction.encode(self.allocator, .{
        if (deposit_data.creation)
            comptime try utils.addressToBytes("0x0000000000000000000000000000000000000000")
        else
            deposit_envelope.to orelse return error.ExpectedToAddress,
        deposit_data.mint,
        deposit_data.gas,
        deposit_data.creation,
        deposit_data.data.?,
    });
    defer self.allocator.free(data);

    const gas = try self.estimateDepositTransaction(data);
    defer gas.deinit();

    const call: LondonEthCall = .{
        .to = contracts.portalAddress,
        .from = address,
        .gas = gas.response,
        .data = data,
        .value = deposit_data.value,
    };

    const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = call }, null);
    const nonce = try self.rpc_client.getAddressTransactionCount(.{
        .address = self.signer.address_bytes,
        .tag = .pending,
    });
    defer nonce.deinit();

    const tx: UnpreparedTransactionEnvelope = .{
        .gas = gas.response,
        .type = .london,
        .data = data,
        .to = contracts.portalAddress,
        .value = deposit_data.value,
        .accessList = &.{},
        .nonce = nonce.response,
        .chainId = @intFromEnum(self.rpc_client.network_config.chain_id),
        .maxFeePerGas = fees.london.max_fee_gas,
        .maxPriorityFeePerGas = fees.london.max_priority_fee,
    };

    return self.sendTransaction(tx);
}

/// Estimate the gas cost for the deposit transaction.
/// Uses the portalAddress. The data is expected to be hex abi encoded data.
pub fn estimateDepositTransaction(
    self: *Wallet,
    data: []u8,
) !RPCResponse(u64) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    return self.rpc_client.estimateGas(.{ .london = .{
        .to = contracts.portalAddress,
        .data = data,
    } }, .{});
}

/// Estimates the gas cost for calling `initiateWithdrawal`
pub fn estimateInitiateWithdrawal(
    self: *Wallet,
    data: []u8,
) !RPCResponse(u64) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    return self.rpc_client.estimateGas(.{ .london = .{
        .to = contracts.l2ToL1MessagePasser,
        .data = data,
    } }, .{});
}

/// Estimates the gas cost for calling `finalizeWithdrawal`
pub fn estimateFinalizeWithdrawal(
    self: *Wallet,
    data: []u8,
) !RPCResponse(u64) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    return self.rpc_client.estimateGas(.{ .london = .{
        .to = contracts.portalAddress,
        .data = data,
    } }, .{});
}

/// Estimates the gas cost for calling `proveWithdrawal`
pub fn estimateProveWithdrawal(
    self: *Wallet,
    data: []u8,
) !RPCResponse(u64) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    return self.rpc_client.estimateGas(.{ .london = .{
        .to = contracts.portalAddress,
        .data = data,
    } }, .{});
}

/// Find a specific prepared envelope from the pool based on the given search criteria.
pub fn findTransactionEnvelopeFromPool(
    self: *Wallet,
    search: TransactionEnvelopePool.SearchCriteria,
) ?TransactionEnvelope {
    return self.envelopes_pool.findTransactionEnvelope(self.allocator, search);
}

/// Invokes the contract method to `finalizeWithdrawalTransaction`. This will send
/// a transaction to the network.
pub fn finalizeWithdrawal(
    self: *Wallet,
    withdrawal: WithdrawalNoHash,
) !RPCResponse(Hash) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const address = self.signer.address_bytes;
    const data = try abi_op.finalize_withdrawal.encodeFromReflection(self.allocator, .{withdrawal});
    defer self.allocator.free(data);

    const gas = try self.estimateFinalizeWithdrawal(data);
    defer gas.deinit();

    const call: LondonEthCall = .{
        .to = contracts.portalAddress,
        .from = address,
        .gas = gas.response,
        .data = data,
    };

    const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = call }, null);
    const nonce = try self.rpc_client.getAddressTransactionCount(.{
        .address = self.signer.address_bytes,
        .tag = .pending,
    });
    defer nonce.deinit();

    const tx: UnpreparedTransactionEnvelope = .{
        .gas = gas.response,
        .data = data,
        .type = .london,
        .to = contracts.portalAddress,
        .value = 0,
        .accessList = &.{},
        .nonce = nonce.response,
        .chainId = @intFromEnum(self.rpc_client.network_config.chain_id),
        .maxFeePerGas = fees.london.max_fee_gas,
        .maxPriorityFeePerGas = fees.london.max_priority_fee,
    };

    return self.sendTransaction(tx);
}

/// Get the wallet address.
///
/// Uses the wallet public key to generate the address.
pub fn getWalletAddress(self: *Wallet) Address {
    return self.signer.address_bytes;
}

/// Generates the authorization hash based on the eip7702 specification.
/// For more information please go [here](https://eips.ethereum.org/EIPS/eip-7702)
///
/// This is still experimental since the EIP has not being deployed into any mainnet.
pub fn hashAuthorityEip7702(
    self: *Wallet,
    authority: Address,
    nonce: u64,
) !Hash {
    const envelope: struct { u64, Address, u64 } = .{
        @intFromEnum(self.rpc_client.network_config.chain_id),
        authority,
        nonce,
    };

    var alloc_writer: std.Io.Writer.Allocating = .init(self.allocator);
    errdefer alloc_writer.deinit();

    try alloc_writer.writer.writeByte(0x05);
    try zabi_encoding.RlpEncoder.encodeRlpFromWriter(self.allocator, envelope, &alloc_writer.writer);

    const serialized = try alloc_writer.toOwnedSlice();
    defer self.allocator.free(serialized);

    var buffer: Hash = undefined;
    Keccak256.hash(serialized, &buffer, .{});

    return buffer;
}

/// Invokes the contract method to `initiateWithdrawal`. This will send
/// a transaction to the network.
pub fn initiateWithdrawal(
    self: *Wallet,
    request: WithdrawalRequest,
) !RPCResponse(Hash) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const address = self.signer.address_bytes;

    const prepared = try self.prepareInitiateWithdrawal(request);
    const data = try abi_op.initiate_withdrawal.encode(self.allocator, .{
        prepared.to,
        prepared.gas,
        prepared.data,
    });
    defer self.allocator.free(data);

    const gas = try self.estimateInitiateWithdrawal(data);
    defer gas.deinit();

    const call: LondonEthCall = .{
        .to = contracts.l2ToL1MessagePasser,
        .from = address,
        .gas = gas.response,
        .data = data,
        .value = prepared.value,
    };
    const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = call }, null);
    const nonce = try self.rpc_client.getAddressTransactionCount(.{
        .address = self.signer.address_bytes,
        .tag = .pending,
    });
    defer nonce.deinit();

    const tx: UnpreparedTransactionEnvelope = .{
        .gas = gas.response,
        .type = .london,
        .data = data,
        .to = contracts.l2ToL1MessagePasser,
        .value = prepared.value,
        .accessList = &.{},
        .nonce = nonce.response,
        .chainId = @intFromEnum(self.rpc_client.network_config.chain_id),
        .maxFeePerGas = fees.london.max_fee_gas,
        .maxPriorityFeePerGas = fees.london.max_priority_fee,
    };

    return self.sendTransaction(tx);
}

/// Converts unprepared transaction envelopes and stores them in a pool.
///
/// This appends to the last node of the list.
pub fn poolTransactionEnvelope(
    self: *Wallet,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) !void {
    const envelope = try self.allocator.create(TransactionEnvelopePool.Node);
    errdefer self.allocator.destroy(envelope);

    envelope.* = .{
        .data = undefined,
        .pool_node = .{},
    };

    envelope.data = try self.prepareTransaction(unprepared_envelope);
    self.envelopes_pool.addEnvelopeToPool(envelope);
}

/// Prepares the deposit transaction. Will error if its a creation transaction
/// and a `to` address was given. It will also fail if the mint and value do not match.
pub fn prepareDepositTransaction(
    self: *Wallet,
    deposit_envelope: DepositEnvelope,
) !DepositData {
    const mint = deposit_envelope.mint orelse 0;
    const value = deposit_envelope.value orelse 0;
    const data = deposit_envelope.data orelse @constCast("");

    if (deposit_envelope.creation and deposit_envelope.to != null)
        return error.CreatingContractToKnowAddress;

    if (mint != value)
        return error.InvalidMintValue;

    const gas = gas: {
        if (deposit_envelope.gas) |gas| break :gas gas;

        const gas = try self.rpc_client.estimateGas(.{ .london = .{
            .value = value,
            .to = deposit_envelope.to,
            .from = self.signer.address_bytes,
        } }, .{});
        defer gas.deinit();

        break :gas gas.response;
    };

    return .{
        .value = value,
        .gas = gas,
        .creation = deposit_envelope.creation,
        .data = data,
        .mint = mint,
    };
}

/// Prepares the interaction with the contract method to `initiateWithdrawal`.
pub fn prepareInitiateWithdrawal(
    self: *Wallet,
    request: WithdrawalRequest,
) !PreparedWithdrawal {
    const gas = gas: {
        if (request.gas) |gas| break :gas gas;

        const gas = try self.rpc_client.estimateGas(.{ .london = .{
            .to = request.to,
            .data = request.data,
            .value = request.value,
        } }, .{});
        defer gas.deinit();

        break :gas gas.response;
    };

    const data = request.data orelse @constCast("");
    const value = request.value orelse 0;

    return .{
        .gas = gas,
        .value = value,
        .data = data,
        .to = request.to,
    };
}

/// Prepares a transaction based on it's type so that it can be sent through the network.\
///
/// Only the null struct properties will get changed.\
/// Everything that gets set before will not be touched.
pub fn prepareTransaction(
    self: *Wallet,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) !TransactionEnvelope {
    switch (unprepared_envelope.type) {
        .cancun => {
            var tx: CancunTransactionEnvelope = undefined;

            tx.chainId = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
            tx.accessList = unprepared_envelope.accessList orelse &.{};
            tx.to = unprepared_envelope.to;
            tx.maxFeePerBlobGas = unprepared_envelope.maxFeePerBlobGas orelse try self.rpc_client.estimateBlobMaxFeePerGas();
            tx.blobVersionedHashes = unprepared_envelope.blobVersionedHashes orelse &.{};
            tx.value = unprepared_envelope.value orelse 0;
            tx.data = unprepared_envelope.data;
            tx.nonce = unprepared_envelope.nonce orelse blk: {
                if (self.nonce_manager) |*manager| {
                    const nonce = try manager.updateNonce(self.rpc_client);

                    break :blk nonce;
                } else {
                    const nonce = try self.rpc_client.getAddressTransactionCount(.{
                        .address = self.signer.address_bytes,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    break :blk nonce.response;
                }
            };

            const curr_block = try self.rpc_client.getBlockByNumber(.{});
            defer curr_block.deinit();

            const base_fee = switch (curr_block.response) {
                inline else => |block_info| block_info.baseFeePerGas,
            };

            const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = .{
                .to = unprepared_envelope.to,
                .from = self.signer.address_bytes,
                .value = tx.value,
                .data = tx.data,
            } }, base_fee);

            tx.maxPriorityFeePerGas = blk: {
                if (unprepared_envelope.maxFeePerGas) |gas| {
                    if (gas < fees.london.max_priority_fee)
                        return error.MaxFeePerGasUnderflow;

                    break :blk gas;
                }

                break :blk fees.london.max_priority_fee;
            };
            tx.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;
            tx.gas = unprepared_envelope.gas orelse blk: {
                const gas = try self.rpc_client.estimateGas(.{
                    .london = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                        .maxFeePerGas = tx.maxFeePerGas,
                        .maxPriorityFeePerGas = tx.maxPriorityFeePerGas,
                    },
                }, .{});
                defer gas.deinit();

                break :blk gas.response;
            };

            return .{ .cancun = tx };
        },
        .london => {
            var tx: LondonTransactionEnvelope = undefined;

            tx.chainId = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
            tx.accessList = unprepared_envelope.accessList orelse &.{};
            tx.value = unprepared_envelope.value orelse 0;
            tx.data = unprepared_envelope.data;
            tx.to = unprepared_envelope.to;
            tx.nonce = unprepared_envelope.nonce orelse blk: {
                if (self.nonce_manager) |*manager| {
                    const nonce = try manager.updateNonce(self.rpc_client);

                    break :blk nonce;
                } else {
                    const nonce = try self.rpc_client.getAddressTransactionCount(.{
                        .address = self.signer.address_bytes,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    break :blk nonce.response;
                }
            };

            const curr_block = try self.rpc_client.getBlockByNumber(.{});
            defer curr_block.deinit();

            const base_fee = switch (curr_block.response) {
                inline else => |block_info| block_info.baseFeePerGas,
            };

            const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = .{
                .to = unprepared_envelope.to,
                .from = self.signer.address_bytes,
                .value = tx.value,
                .data = tx.data,
            } }, base_fee);

            tx.maxPriorityFeePerGas = blk: {
                if (unprepared_envelope.maxFeePerGas) |gas| {
                    if (gas < fees.london.max_priority_fee)
                        return error.MaxFeePerGasUnderflow;

                    break :blk gas;
                }

                break :blk fees.london.max_priority_fee;
            };
            tx.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;
            tx.gas = unprepared_envelope.gas orelse blk: {
                const gas = try self.rpc_client.estimateGas(.{
                    .london = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                        .maxFeePerGas = tx.maxFeePerGas,
                        .maxPriorityFeePerGas = tx.maxPriorityFeePerGas,
                    },
                }, .{});
                defer gas.deinit();

                break :blk gas.response;
            };

            return .{ .london = tx };
        },
        .berlin => {
            var tx: BerlinTransactionEnvelope = undefined;

            tx.chainId = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
            tx.accessList = unprepared_envelope.accessList orelse &.{};
            tx.value = unprepared_envelope.value orelse 0;
            tx.to = unprepared_envelope.to;
            tx.data = unprepared_envelope.data;
            tx.nonce = unprepared_envelope.nonce orelse blk: {
                if (self.nonce_manager) |*manager| {
                    const nonce = try manager.updateNonce(self.rpc_client);

                    break :blk nonce;
                } else {
                    const nonce = try self.rpc_client.getAddressTransactionCount(.{
                        .address = self.signer.address_bytes,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    break :blk nonce.response;
                }
            };

            const curr_block = try self.rpc_client.getBlockByNumber(.{});
            defer curr_block.deinit();

            const base_fee = switch (curr_block.response) {
                inline else => |block_info| block_info.baseFeePerGas,
            };

            tx.gasPrice = unprepared_envelope.gasPrice orelse blk: {
                const fees = try self.rpc_client.estimateFeesPerGas(.{
                    .legacy = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                    },
                }, base_fee);

                break :blk fees.legacy.gas_price;
            };
            tx.gas = unprepared_envelope.gas orelse blk: {
                const gas = try self.rpc_client.estimateGas(.{
                    .legacy = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                        .gasPrice = tx.gasPrice,
                    },
                }, .{});
                defer gas.deinit();

                break :blk gas.response;
            };

            return .{ .berlin = tx };
        },
        .legacy => {
            var tx: LegacyTransactionEnvelope = undefined;

            tx.chainId = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
            tx.value = unprepared_envelope.value orelse 0;
            tx.data = unprepared_envelope.data;
            tx.to = unprepared_envelope.to;
            tx.nonce = unprepared_envelope.nonce orelse blk: {
                if (self.nonce_manager) |*manager| {
                    const nonce = try manager.updateNonce(self.rpc_client);

                    break :blk nonce;
                } else {
                    const nonce = try self.rpc_client.getAddressTransactionCount(.{
                        .address = self.signer.address_bytes,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    break :blk nonce.response;
                }
            };

            const curr_block = try self.rpc_client.getBlockByNumber(.{});
            defer curr_block.deinit();

            const base_fee = switch (curr_block.response) {
                inline else => |block_info| block_info.baseFeePerGas,
            };

            tx.gasPrice = unprepared_envelope.gasPrice orelse blk: {
                const fees = try self.rpc_client.estimateFeesPerGas(.{ .legacy = .{
                    .to = unprepared_envelope.to,
                    .from = self.signer.address_bytes,
                    .value = tx.value,
                    .data = tx.data,
                } }, base_fee);

                break :blk fees.legacy.gas_price;
            };
            tx.gas = unprepared_envelope.gas orelse blk: {
                const gas = try self.rpc_client.estimateGas(.{
                    .legacy = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                        .gasPrice = tx.gasPrice,
                    },
                }, .{});
                defer gas.deinit();

                break :blk gas.response;
            };

            return .{ .legacy = tx };
        },
        .eip7702 => {
            var tx: Eip7702TransactionEnvelope = undefined;

            tx.chainId = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
            tx.accessList = unprepared_envelope.accessList orelse &.{};
            tx.authorizationList = unprepared_envelope.authList orelse &.{};
            tx.to = unprepared_envelope.to;
            tx.value = unprepared_envelope.value orelse 0;
            tx.data = unprepared_envelope.data;
            tx.nonce = unprepared_envelope.nonce orelse blk: {
                if (self.nonce_manager) |*manager| {
                    const nonce = try manager.updateNonce(self.rpc_client);

                    break :blk nonce;
                } else {
                    const nonce = try self.rpc_client.getAddressTransactionCount(.{
                        .address = self.signer.address_bytes,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    break :blk nonce.response;
                }
            };

            const curr_block = try self.rpc_client.getBlockByNumber(.{});
            defer curr_block.deinit();

            const base_fee = switch (curr_block.response) {
                inline else => |block_info| block_info.baseFeePerGas,
            };

            const fees = try self.rpc_client.estimateFeesPerGas(.{
                .london = .{
                    .to = unprepared_envelope.to,
                    .from = self.signer.address_bytes,
                    .value = tx.value,
                    .data = tx.data,
                },
            }, base_fee);

            tx.maxPriorityFeePerGas = blk: {
                if (unprepared_envelope.maxFeePerGas) |gas| {
                    if (gas < fees.london.max_priority_fee)
                        return error.MaxFeePerGasUnderflow;

                    break :blk gas;
                }

                break :blk fees.london.max_priority_fee;
            };
            tx.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;
            tx.gas = unprepared_envelope.gas orelse blk: {
                const gas = try self.rpc_client.estimateGas(.{
                    .london = .{
                        .to = unprepared_envelope.to,
                        .from = self.signer.address_bytes,
                        .value = tx.value,
                        .data = tx.data,
                        .maxFeePerGas = tx.maxFeePerGas,
                        .maxPriorityFeePerGas = tx.maxPriorityFeePerGas,
                    },
                }, .{});
                defer gas.deinit();

                break :blk gas.response;
            };

            return .{ .eip7702 = tx };
        },
        .deposit => return error.UnsupportedTransactionType,
        _ => return error.UnsupportedTransactionType,
    }
}

/// Prepares a proof withdrawal transaction.
pub fn prepareWithdrawalProofTransaction(
    self: *Wallet,
    withdrawal: Withdrawal,
    l2_output: L2Output,
) !WithdrawalEnvelope {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const storage_slot = op_utils.getWithdrawalHashStorageSlot(withdrawal.withdrawalHash);
    const proof = try self.rpc_client.getProof(.{
        .address = contracts.l2ToL1MessagePasser,
        .storageKeys = &.{storage_slot},
        .blockNumber = @intCast(l2_output.l2BlockNumber),
    }, null);
    defer proof.deinit();

    const block = try self.rpc_client.getBlockByNumber(.{ .block_number = @intCast(l2_output.l2BlockNumber) });
    defer block.deinit();

    const block_info: struct { stateRoot: Hash, hash: Hash } = switch (block.response) {
        inline else => |block_info| .{ .stateRoot = block_info.stateRoot, .hash = block_info.hash.? },
    };

    var proofs = try std.array_list.Managed([]u8).initCapacity(self.allocator, proof.response.storageProof[0].proof.len);
    errdefer proofs.deinit();

    for (proof.response.storageProof[0].proof) |p| {
        proofs.appendAssumeCapacity(try self.allocator.dupe(u8, p));
    }

    return .{
        .nonce = withdrawal.nonce,
        .sender = withdrawal.sender,
        .target = withdrawal.target,
        .value = withdrawal.value,
        .gasLimit = withdrawal.gasLimit,
        .data = withdrawal.data,
        .outputRootProof = .{
            .version = [_]u8{0} ** 32,
            .stateRoot = block_info.stateRoot,
            .messagePasserStorageRoot = proof.response.storageHash,
            .latestBlockhash = block_info.hash,
        },
        .withdrawalProof = try proofs.toOwnedSlice(),
        .l2OutputIndex = l2_output.outputIndex,
    };
}

/// Invokes the contract method to `proveWithdrawalTransaction`. This will send
/// a transaction to the network.
pub fn proveWithdrawal(
    self: *Wallet,
    withdrawal: WithdrawalNoHash,
    l2_output_index: u256,
    outputRootProof: RootProof,
    withdrawal_proof: []const []u8,
) !RPCResponse(Hash) {
    const contracts = self.rpc_client.network_config.op_stack_contracts orelse return error.ExpectedOpStackContracts;

    const address = self.signer.address_bytes;
    const data = try abi_op.prove_withdrawal.encodeFromReflection(self.allocator, .{
        withdrawal, l2_output_index, outputRootProof, withdrawal_proof,
    });
    defer self.allocator.free(data);

    const gas = try self.estimateProveWithdrawal(data);
    defer gas.deinit();

    const call: LondonEthCall = .{
        .to = contracts.portalAddress,
        .from = address,
        .gas = gas.response,
        .data = data,
    };

    const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = call }, null);
    const nonce = try self.rpc_client.getAddressTransactionCount(.{
        .address = self.signer.address_bytes,
        .tag = .pending,
    });
    defer nonce.deinit();

    const tx: UnpreparedTransactionEnvelope = .{
        .gas = gas.response,
        .type = .london,
        .data = data,
        .to = contracts.portalAddress,
        .value = 0,
        .accessList = &.{},
        .nonce = nonce.response,
        .chainId = @intFromEnum(self.rpc_client.network_config.chain_id),
        .maxFeePerGas = fees.london.max_fee_gas,
        .maxPriorityFeePerGas = fees.london.max_priority_fee,
    };

    return self.sendTransaction(tx);
}

/// Uses eth_call to query an contract information.
/// Only abi items that are either `view` or `pure` will be allowed.
/// It won't commit a transaction to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn readContractFunction(
    wallet: *Wallet,
    comptime T: type,
    func: Function,
    function_args: anytype,
    overrides: EthCall,
) !AbiDecoded(T) {
    var copy = overrides;

    switch (func.stateMutability) {
        .view, .pure => {},
        inline else => return error.InvalidFunctionMutability,
    }

    const encoded = try func.encodeFromReflection(wallet.allocator, function_args);
    defer wallet.allocator.free(encoded);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to == null)
                return error.InvalidRequestTarget;

            tx.data = encoded;
        },
    }

    const data = try wallet.rpc_client.sendEthCall(copy, .{});
    defer data.deinit();

    const decoded = try decoder.decodeAbiParameter(T, wallet.allocator, data.response, .{});

    return decoded;
}

/// Uses eth_call to query an contract information.
/// Only abi items that are either `view` or `pure` will be allowed.
/// It won't commit a transaction to the network.
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn readContractFunctionComptime(
    wallet: *Wallet,
    comptime func: Function,
    args: AbiParametersToPrimative(func.inputs),
    overrides: EthCall,
) !AbiDecoded(AbiParametersToPrimative(func.outputs)) {
    var copy = overrides;

    switch (func.stateMutability) {
        .view, .pure => {},
        inline else => return error.InvalidFunctionMutability,
    }

    const encoded = try func.encode(wallet.allocator, args);
    defer if (encoded.len != 0) wallet.allocator.free(encoded);

    switch (copy) {
        inline else => |*tx| {
            if (tx.to == null)
                return error.InvalidRequestTarget;

            tx.data = encoded;
        },
    }

    const data = try wallet.rpc_client.sendEthCall(copy, .{});
    defer data.deinit();

    const decoded = try decoder.decodeAbiParameter(AbiParametersToPrimative(func.outputs), wallet.allocator, data.response, .{});

    return decoded;
}

/// Recovers the address associated with the signature based on the message.\
/// To reconstruct the message use `authMessageEip3074`
///
/// Reconstructs the message from them and returns the address bytes.
pub fn recoverAuthMessageAddress(
    auth_message: []u8,
    sig: Signature,
) Signer.RecoverPubKeyErrors!Address {
    var hash: Hash = undefined;
    Keccak256.hash(auth_message, &hash, .{});

    return Signer.recoverAddress(sig, hash);
}

/// Recovers the address associated with the signature based on the authorization payload.
pub fn recoverAuthorizationAddress(
    self: *Wallet,
    authorization_payload: AuthorizationPayload,
) !Address {
    const hash = try self.hashAuthorityEip7702(authorization_payload.address, authorization_payload.nonce);

    return Signer.recoverAddress(.{
        .v = @truncate(authorization_payload.y_parity),
        .r = authorization_payload.r,
        .s = authorization_payload.s,
    }, hash);
}

/// Search the internal `TransactionEnvelopePool` to find the specified transaction based on the `type` and nonce.
///
/// If there are duplicate transaction that meet the search criteria it will send the first it can find.\
/// The search is linear and starts from the first node of the pool.
pub fn searchPoolAndSendTransaction(
    self: *Wallet,
    search_opts: TransactionEnvelopePool.SearchCriteria,
) !RPCResponse(Hash) {
    const prepared = self.envelopes_pool.findTransactionEnvelope(self.allocator, search_opts) orelse
        return error.TransactionNotFoundInPool;

    try self.assertTransaction(prepared);

    return self.sendSignedTransaction(prepared);
}

/// Sends blob transaction to the network.
/// Trusted setup must be loaded otherwise this will fail.
pub fn sendBlobTransaction(
    self: *Wallet,
    blobs: []const Blob,
    unprepared_envelope: UnpreparedTransactionEnvelope,
    trusted_setup: *KZG4844,
) !RPCResponse(Hash) {
    if (unprepared_envelope.type != .cancun)
        return error.InvalidTransactionType;

    if (!trusted_setup.loaded)
        return error.TrustedSetupNotLoaded;

    const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse
        try self.prepareTransaction(unprepared_envelope);

    try self.assertTransaction(prepared);

    const serialized = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, null, blobs, trusted_setup);
    defer self.allocator.free(serialized);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &hash_buffer, .{});

    const signed = try self.signer.sign(hash_buffer);
    const serialized_signed = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, signed, blobs, trusted_setup);
    defer self.allocator.free(serialized_signed);

    return self.rpc_client.sendRawTransaction(serialized_signed);
}

/// Sends blob transaction to the network.
/// This uses and already prepared sidecar.
pub fn sendSidecarTransaction(
    self: *Wallet,
    sidecars: []const Sidecar,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    if (unprepared_envelope.type != .cancun)
        return error.InvalidTransactionType;

    const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse
        try self.prepareTransaction(unprepared_envelope);

    try self.assertTransaction(prepared);

    const serialized = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, null, sidecars);
    defer self.allocator.free(serialized);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &hash_buffer, .{});

    const signed = try self.signer.sign(hash_buffer);
    const serialized_signed = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, signed, sidecars);
    defer self.allocator.free(serialized_signed);

    return self.rpc_client.sendRawTransaction(serialized_signed);
}

/// Signs, serializes and send the transaction via `eth_sendRawTransaction`.
///
/// Returns the transaction hash.
pub fn sendSignedTransaction(
    self: *Wallet,
    tx: TransactionEnvelope,
) !RPCResponse(Hash) {
    const serialized = try serialize.serializeTransaction(self.allocator, tx, null);
    defer self.allocator.free(serialized);

    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(serialized, &hash_buffer, .{});

    const signed = try self.signer.sign(hash_buffer);
    const serialized_signed = try serialize.serializeTransaction(self.allocator, tx, signed);
    defer self.allocator.free(serialized_signed);

    return self.rpc_client.sendRawTransaction(serialized_signed);
}

/// Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.
///
/// If any envelope is in the envelope pool it will use that instead in a LIFO order.\
/// Will return an error if the envelope is incorrect
pub fn sendTransaction(
    self: *Wallet,
    unprepared_envelope: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse
        try self.prepareTransaction(unprepared_envelope);

    try self.assertTransaction(prepared);

    return self.sendSignedTransaction(prepared);
}

/// Signs and prepares an eip7702 authorization message.
/// For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-7702#specification).
///
/// You can pass null to `nonce` if you want to target a specific nonce.\
/// Otherwise if with either use the `nonce_manager` if it can or fetch from the network.
///
/// This is still experimental since the EIP has not being deployed into any mainnet.
pub fn signAuthorizationEip7702(
    self: *Wallet,
    authority: Address,
    nonce: ?u64,
) !AuthorizationPayload {
    const nonce_from = nonce: {
        if (nonce) |nonce_unwrapped|
            break :nonce nonce_unwrapped;

        if (self.nonce_manager) |*manager|
            break :nonce try manager.getNonce(self.rpc_client);

        const rpc_nonce = try self.rpc_client.getAddressTransactionCount(.{
            .tag = .pending,
            .address = self.signer.address_bytes,
        });
        defer rpc_nonce.deinit();

        break :nonce rpc_nonce.response;
    };

    const hash = try self.hashAuthorityEip7702(authority, nonce_from);
    const signature = try self.signer.sign(hash);

    return .{
        .chain_id = @intFromEnum(self.rpc_client.network_config.chain_id),
        .nonce = nonce_from,
        .address = authority,
        .y_parity = signature.v,
        .r = signature.r,
        .s = signature.s,
    };
}

/// Signs an ethereum message with the specified prefix.
///
/// The Signatures recoverId doesn't include the chain_id.
pub fn signEthereumMessage(
    self: *Wallet,
    message: []const u8,
) !Signature {
    const start = "\x19Ethereum Signed Message:\n";
    const concated_message = try std.fmt.allocPrint(self.allocator, "{s}{d}{s}", .{ start, message.len, message });
    defer self.allocator.free(concated_message);

    var hash: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(concated_message, &hash, .{});

    return self.signer.sign(hash);
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
/// Returns the signature type.
pub fn signTypedData(
    self: *Wallet,
    comptime eip_types: anytype,
    comptime primary_type: []const u8,
    domain: ?TypedDataDomain,
    message: anytype,
) !Signature {
    return self.signer.sign(try eip712.hashTypedData(
        self.allocator,
        eip_types,
        primary_type,
        domain,
        message,
    ));
}

/// Uses eth_call to simulate a contract interaction.
/// It won't commit a transaction to the network.
/// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn simulateWriteCall(
    wallet: *Wallet,
    func: Function,
    function_args: anytype,
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse([]u8) {
    var copy = overrides;

    const encoded = try func.encodeFromReflection(wallet.allocator, function_args);
    defer if (encoded.len != 0) wallet.allocator.free(encoded);

    if (copy.to == null)
        return error.InvalidRequestTarget;

    copy.data = encoded;

    const address = wallet.getWalletAddress();
    const call: EthCall = switch (copy.type) {
        .cancun,
        .london,
        .eip7702,
        => .{ .london = .{
            .from = address,
            .to = copy.to,
            .data = copy.data,
            .value = copy.value,
            .maxFeePerGas = copy.maxFeePerGas,
            .maxPriorityFeePerGas = copy.maxPriorityFeePerGas,
            .gas = copy.gas,
        } },
        .berlin,
        .legacy,
        => .{ .legacy = .{
            .from = address,
            .value = copy.value,
            .to = copy.to,
            .data = copy.data,
            .gas = copy.gas,
            .gasPrice = copy.gasPrice,
        } },
        .deposit => return error.UnsupportedTransactionType,
        _ => return error.UnsupportedTransactionType,
    };

    return wallet.rpc_client.sendEthCall(call, .{});
}

/// Uses eth_call to simulate a contract interaction.
/// It won't commit a transaction to the network.
/// I recommend watching this talk to better grasp this: https://www.youtube.com/watch?v=bEUtGLnCCYM (I promise it's not a rick roll)
///
/// RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)
pub fn simulateWriteCallComptime(
    wallet: *Wallet,
    comptime func: Function,
    args: AbiParametersToPrimative(func.inputs),
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse([]u8) {
    var copy = overrides;

    const encoded = try func.encode(wallet.allocator, args);
    defer if (encoded.len != 0) wallet.allocator.free(encoded);

    if (copy.to == null)
        return error.InvalidRequestTarget;

    copy.data = encoded;

    const address = wallet.getWalletAddress();
    const call: EthCall = switch (copy.type) {
        .cancun,
        .london,
        .eip7702,
        => .{
            .london = .{
                .from = address,
                .to = copy.to,
                .data = copy.data,
                .value = copy.value,
                .maxFeePerGas = copy.maxFeePerGas,
                .maxPriorityFeePerGas = copy.maxPriorityFeePerGas,
                .gas = copy.gas,
            },
        },
        .berlin,
        .legacy,
        => .{
            .legacy = .{
                .from = address,
                .value = copy.value,
                .to = copy.to,
                .data = copy.data,
                .gas = copy.gas,
                .gasPrice = copy.gasPrice,
            },
        },
        .deposit => return error.UnsupportedTransactionType,
        _ => return error.UnsupportedTransactionType,
    };

    return wallet.rpc_client.sendEthCall(call, .{});
}

/// Verifies if the authorization message was signed by the provided address.\
///
/// You can pass null to `expected_address` if you want to use this wallet instance
/// associated address.
pub fn verifyAuthorization(
    self: *Wallet,
    expected_address: ?Address,
    authorization_payload: AuthorizationPayload,
) !bool {
    const expected_addr: u160 = @bitCast(expected_address orelse self.signer.address_bytes);

    const recovered_address: u160 = @bitCast(try self.recoverAuthorizationAddress(authorization_payload));

    return expected_addr == recovered_address;
}
/// Verifies if a given signature was signed by the current wallet.
pub fn verifyMessage(self: *Wallet, sig: Signature, message: []const u8) bool {
    var hash_buffer: [Keccak256.digest_length]u8 = undefined;
    Keccak256.hash(message, &hash_buffer, .{});
    return self.signer.verifyMessage(hash_buffer, sig);
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
/// Returns the signature type.
pub fn verifyTypedData(
    self: *Wallet,
    sig: Signature,
    comptime eip712_types: anytype,
    comptime primary_type: []const u8,
    domain: ?TypedDataDomain,
    message: anytype,
) !bool {
    const hash = try eip712.hashTypedData(
        self.allocator,
        eip712_types,
        primary_type,
        domain,
        message,
    );

    const address: u160 = @bitCast(try Signer.recoverAddress(sig, hash));
    const wallet_address: u160 = @bitCast(self.getWalletAddress());

    return address == wallet_address;
}

/// Encodes the function arguments based on the function abi item.
/// Only abi items that are either `payable` or `nonpayable` will be allowed.
/// It will send the transaction to the network and return the transaction hash.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn writeContractFunction(
    wallet: *Wallet,
    func: Function,
    function_args: anytype,
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    var copy = overrides;

    switch (func.stateMutability) {
        .nonpayable, .payable => {},
        inline else => return error.InvalidFunctionMutability,
    }

    if (copy.to == null)
        return error.InvalidRequestTarget;

    const value = copy.value orelse 0;
    switch (func.stateMutability) {
        .nonpayable => if (value != 0)
            return error.ValueInNonPayableFunction,
        .payable => {},
        inline else => return error.InvalidFunctionMutability,
    }

    copy.data = try func.encodeFromReflection(wallet.allocator, function_args);
    defer wallet.allocator.free(copy.data.?);

    return wallet.sendTransaction(copy);
}

/// Encodes the function arguments based on the function abi item.
/// Only abi items that are either `payable` or `nonpayable` will be allowed.
/// It will send the transaction to the network and return the transaction hash.
///
/// RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)
pub fn writeContractFunctionComptime(
    wallet: *Wallet,
    comptime func: Function,
    args: AbiParametersToPrimative(func.inputs),
    overrides: UnpreparedTransactionEnvelope,
) !RPCResponse(Hash) {
    var copy = overrides;

    if (copy.to == null)
        return error.InvalidRequestTarget;

    const value = copy.value orelse 0;
    switch (func.stateMutability) {
        .nonpayable => if (value != 0)
            return error.ValueInNonPayableFunction,
        .payable => {},
        inline else => return error.InvalidFunctionMutability,
    }

    copy.data = try func.encode(wallet.allocator, args);
    defer wallet.allocator.free(copy.data.?);

    return wallet.sendTransaction(copy);
}
