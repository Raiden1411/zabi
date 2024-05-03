const kzg = @import("c-kzg-4844");
const log = @import("log.zig");
const meta = @import("../meta/root.zig");
const op_transactions = @import("../clients/optimism/types/transaction.zig");
const std = @import("std");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Blob = kzg.KZG4844.Blob;
const DepositTransactionSigned = op_transactions.DepositTransactionSigned;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const KZGCommitment = kzg.KZG4844.KZGCommitment;
const KZGProof = kzg.KZG4844.KZGProof;
const Logs = log.Logs;
const Merge = meta.utils.MergeTupleStructs;
const Omit = meta.utils.Omit;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const RequestParser = meta.json.RequestParser;
const StructToTupleType = meta.utils.StructToTupleType;
const Token = std.json.Token;
const Value = std.json.Value;
const Wei = types.Wei;

/// Tuple representig an encoded envelope for the Berlin hardfork
pub const BerlinEnvelope = StructToTupleType(BerlinTransactionEnvelope);
/// Tuple representig an encoded envelope for the Berlin hardfork with the signature
pub const BerlinEnvelopeSigned = StructToTupleType(BerlinTransactionEnvelopeSigned);
/// Tuple representig an encoded envelope for a legacy transaction
pub const LegacyEnvelope = StructToTupleType(Omit(LegacyTransactionEnvelope, &.{"chainId"}));
/// Tuple representig an encoded envelope for a legacy transaction
pub const LegacyEnvelopeSigned = StructToTupleType(Omit(LegacyTransactionEnvelopeSigned, &.{"chainId"}));
/// Tuple representig an encoded envelope for the London hardfork
pub const LondonEnvelope = StructToTupleType(LondonTransactionEnvelope);
/// Tuple representig an encoded envelope for the London hardfork with the signature
pub const LondonEnvelopeSigned = StructToTupleType(LondonTransactionEnvelopeSigned);
/// Tuple representig an encoded envelope for the London hardfork
pub const CancunEnvelope = StructToTupleType(CancunTransactionEnvelope);
/// Tuple representig an encoded envelope for the London hardfork with the signature
pub const CancunEnvelopeSigned = StructToTupleType(CancunTransactionEnvelopeSigned);
/// Signed cancun transaction converted to wrapper with blobs, commitments and proofs
pub const CancunSignedWrapper = Merge(StructToTupleType(CancunTransactionEnvelopeSigned), struct { []const Blob, []const KZGCommitment, []const KZGProof });
/// Cancun transaction converted to wrapper with blobs, commitments and proofs
pub const CancunWrapper = Merge(StructToTupleType(CancunTransactionEnvelope), struct { []const Blob, []const KZGCommitment, []const KZGProof });

pub const TransactionTypes = enum(u8) { legacy = 0x00, berlin = 0x01, london = 0x02, cancun = 0x03, deposit = 0x7e, _ };

/// The transaction envelope that will be serialized before getting sent to the network.
pub const TransactionEnvelope = union(enum) {
    berlin: BerlinTransactionEnvelope,
    cancun: CancunTransactionEnvelope,
    legacy: LegacyTransactionEnvelope,
    london: LondonTransactionEnvelope,
};
/// The transaction envelope from the Cancun hardfork
pub const CancunTransactionEnvelope = struct {
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    maxFeePerBlobGas: Gwei,
    blobVersionedHashes: ?[]const Hash = null,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the London hardfork
pub const LondonTransactionEnvelope = struct {
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork
pub const BerlinTransactionEnvelope = struct {
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction
pub const LegacyTransactionEnvelope = struct {
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// Struct representing the accessList field.
pub const AccessList = struct {
    address: Address,
    storageKeys: []const Hash,

    pub usingnamespace RequestParser(@This());
};
/// Struct representing the result of create accessList
pub const AccessListResult = struct {
    accessList: []const AccessList,
    gasUsed: Gwei,

    pub usingnamespace RequestParser(@This());
};
/// Signed transaction envelope with the signature fields
pub const TransactionEnvelopeSigned = union(enum) {
    berlin: BerlinTransactionEnvelopeSigned,
    cancun: CancunTransactionEnvelopeSigned,
    legacy: LegacyTransactionEnvelopeSigned,
    london: LondonTransactionEnvelopeSigned,
};
/// The transaction envelope from the London hardfork with the signature fields
pub const CancunTransactionEnvelopeSigned = struct {
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    maxFeePerBlobGas: Gwei,
    blobVersionedHashes: ?[]const Hash = null,
    v: u2,
    r: Hash,
    s: Hash,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the London hardfork with the signature fields
pub const LondonTransactionEnvelopeSigned = struct {
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    v: u2,
    r: Hash,
    s: Hash,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork with the signature fields
pub const BerlinTransactionEnvelopeSigned = struct {
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    v: u2,
    r: Hash,
    s: Hash,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction with the signature fields
pub const LegacyTransactionEnvelopeSigned = struct {
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    v: usize,
    r: ?Hash,
    s: ?Hash,

    pub usingnamespace RequestParser(@This());
};
/// Same as `Envelope` but were all fields are optionals.
pub const UnpreparedTransactionEnvelope = struct {
    type: TransactionTypes,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    maxFeePerBlobGas: ?Gwei = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    gasPrice: ?Gwei = null,
    to: ?Address = null,
    value: ?Wei = null,
    data: ?Hex = null,
    accessList: ?[]const AccessList = null,
    blobVersionedHashes: ?[]const Hash = null,
};
/// The representation of a London hardfork pending transaction.
pub const LondonPendingTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    type: TransactionTypes,
    accessList: []const AccessList,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    yParity: u1,

    pub usingnamespace RequestParser(@This());
};
/// The legacy representation of a pending transaction.
pub const LegacyPendingTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: usize,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    type: TransactionTypes,
    chainId: ?usize = null,

    pub usingnamespace RequestParser(@This());
};
/// The Cancun hardfork representation of a transaction.
pub const L2Transaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: usize,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    sourceHash: ?Hash = null,
    isSystemTx: ?bool = null,
    index: u64,
    l1BlockNumber: u64,
    l1Timestamp: u64,
    l1TxOrigin: ?Hash,
    queueIndex: ?u64,
    queueOrigin: []const u8,
    rawTransaction: Hex,

    pub usingnamespace RequestParser(@This());
};
/// The Cancun hardfork representation of a transaction.
pub const CancunTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    sourceHash: ?Hash = null,
    isSystemTx: ?bool = null,
    type: TransactionTypes,
    accessList: []const AccessList,
    blobVersionedHashes: []const Hash,
    maxFeePerBlobGas: Gwei,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    yParity: ?u1 = null,

    pub usingnamespace RequestParser(@This());
};
/// The London hardfork representation of a transaction.
pub const LondonTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    sourceHash: ?Hash = null,
    isSystemTx: ?bool = null,
    type: TransactionTypes,
    accessList: []const AccessList,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    yParity: ?u1 = null,

    pub usingnamespace RequestParser(@This());
};
/// The Berlin hardfork representation of a transaction.
pub const BerlinTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u8,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    sourceHash: ?Hash = null,
    isSystemTx: ?bool = null,
    type: TransactionTypes,
    accessList: []const AccessList,
    chainId: usize,
    yParity: ?u1 = null,

    pub usingnamespace RequestParser(@This());
};
/// The legacy representation of a transaction.
pub const LegacyTransaction = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: usize,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    sourceHash: ?Hash = null,
    isSystemTx: ?bool = null,
    type: ?TransactionTypes = null,
    chainId: ?usize = null,

    pub usingnamespace RequestParser(@This());
};
/// All transactions objects that one might find whilest interaction
/// with the JSON RPC server.
pub const Transaction = union(enum) {
    /// Legacy type transactions.
    legacy: LegacyTransaction,
    /// Berlin hardfork transactions that might have the accessList.
    berlin: BerlinTransaction,
    /// London hardfork transaction objects.
    london: LondonTransaction,
    /// Cancun hardfork transactions.
    cancun: CancunTransaction,
    /// L2 transaction objects
    l2_transaction: L2Transaction,
    /// L2 Deposit transaction
    deposit: DepositTransactionSigned,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        const tx_type = source.object.get("type") orelse if (source.object.get("l1Timestamp") != null)
            return @unionInit(@This(), "l2_transaction", try std.json.parseFromValueLeaky(L2Transaction, allocator, source, options))
        else
            return @unionInit(@This(), "legacy", try std.json.parseFromValueLeaky(LegacyTransaction, allocator, source, options));

        if (source.object.get("l1Timestamp") != null)
            return @unionInit(@This(), "l2_transaction", try std.json.parseFromValueLeaky(L2Transaction, allocator, source, options));

        if (tx_type != .string)
            return error.UnexpectedToken;

        const type_value = try std.fmt.parseInt(u8, tx_type.string, 0);

        switch (type_value) {
            0x00 => return @unionInit(@This(), "legacy", try std.json.parseFromValueLeaky(LegacyTransaction, allocator, source, options)),
            0x01 => return @unionInit(@This(), "berlin", try std.json.parseFromValueLeaky(BerlinTransaction, allocator, source, options)),
            0x02 => return @unionInit(@This(), "london", try std.json.parseFromValueLeaky(LondonTransaction, allocator, source, options)),
            0x03 => return @unionInit(@This(), "cancun", try std.json.parseFromValueLeaky(CancunTransaction, allocator, source, options)),
            0x7e => return @unionInit(@This(), "deposit", try std.json.parseFromValueLeaky(DepositTransactionSigned, allocator, source, options)),
            else => return error.UnexpectedToken,
        }
    }

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};
/// The london and other hardforks transaction receipt representation
pub const LegacyReceipt = struct {
    transactionHash: Hash,
    transactionIndex: u64,
    blockHash: Hash,
    blockNumber: ?u64,
    from: Address,
    to: ?Address,
    cumulativeGasUsed: Gwei,
    effectiveGasPrice: Gwei,
    gasUsed: Gwei,
    contractAddress: ?Address,
    logs: Logs,
    logsBloom: Hex,
    type: ?TransactionTypes = null,
    root: ?Hex = null,
    status: ?bool = null,
    deposit_nonce: ?usize = null,

    pub usingnamespace RequestParser(@This());
};
/// Cancun transaction receipt representation
pub const CancunReceipt = struct {
    transactionHash: Hash,
    transactionIndex: u64,
    blockHash: Hash,
    blockNumber: ?u64,
    from: Address,
    to: ?Address,
    cumulativeGasUsed: Gwei,
    effectiveGasPrice: Gwei,
    blobGasPrice: Gwei,
    blobGasUsed: Gwei,
    gasUsed: Gwei,
    contractAddress: ?Address,
    logs: Logs,
    logsBloom: Hex,
    type: ?TransactionTypes = null,
    root: ?Hex = null,
    status: ?bool = null,
    deposit_nonce: ?usize = null,

    pub usingnamespace RequestParser(@This());
};
/// L2 transaction receipt representation
pub const OpstackReceipt = struct {
    transactionHash: Hash,
    transactionIndex: u64,
    blockHash: Hash,
    blockNumber: ?u64,
    from: Address,
    to: ?Address,
    gasUsed: Gwei,
    cumulativeGasUsed: Gwei,
    contractAddress: ?Address,
    logs: Logs,
    status: ?bool = null,
    logsBloom: Hex,
    type: ?TransactionTypes = null,
    effectiveGasPrice: ?Gwei = null,
    deposit_nonce: ?usize = null,
    l1Fee: Wei,
    l1GasPrice: Gwei,
    l1GasUsed: Gwei,
    l1FeeScalar: ?f64 = null,
    root: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// L2 Deposit transaction receipt representation
pub const DepositReceipt = struct {
    transactionHash: Hash,
    transactionIndex: u64,
    blockHash: Hash,
    blockNumber: ?u64,
    from: Address,
    to: ?Address,
    cumulativeGasUsed: Gwei,
    gasUsed: Gwei,
    contractAddress: ?Address,
    logs: Logs,
    status: ?bool = null,
    logsBloom: Hex,
    type: ?TransactionTypes = null,
    effectiveGasPrice: ?Gwei = null,
    deposit_nonce: ?usize = null,
    depositNonce: ?u64,
    depositNonceVersion: ?u64 = null,
    root: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// Arbitrum transaction receipt representation
pub const ArbitrumReceipt = struct {
    transactionHash: Hash,
    blockHash: Hash,
    blockNumber: ?u64,
    logsBloom: Hex,
    l1BlockNumber: Wei,
    contractAddress: ?Address,
    transactionIndex: u64,
    gasUsedForL1: Gwei,
    type: ?TransactionTypes = null,
    gasUsed: Gwei,
    cumulativeGasUsed: Gwei,
    from: Address,
    to: ?Address,
    effectiveGasPrice: ?Gwei = null,
    logs: Logs,
    root: ?Hex = null,
    status: ?bool = null,
    deposit_nonce: ?usize = null,

    pub usingnamespace RequestParser(@This());
};
/// All possible transaction receipts
pub const TransactionReceipt = union(enum) {
    legacy: LegacyReceipt,
    cancun: CancunReceipt,
    op_receipt: OpstackReceipt,
    arbitrum_receipt: ArbitrumReceipt,
    deposit_receipt: DepositReceipt,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        if (source.object.get("blobGasUsed") != null)
            return @unionInit(@This(), "cancun", try std.json.parseFromValueLeaky(CancunReceipt, allocator, source, options));

        if (source.object.get("l1GasUsed") != null)
            return @unionInit(@This(), "op_receipt", try std.json.parseFromValueLeaky(OpstackReceipt, allocator, source, options));

        if (source.object.get("gasUsedForL1") != null)
            return @unionInit(@This(), "arbitrum_receipt", try std.json.parseFromValueLeaky(ArbitrumReceipt, allocator, source, options));

        if (source.object.get("depositNonce") != null)
            return @unionInit(@This(), "deposit_receipt", try std.json.parseFromValueLeaky(DepositReceipt, allocator, source, options));

        return @unionInit(@This(), "legacy", try std.json.parseFromValueLeaky(LegacyReceipt, allocator, source, options));
    }

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};
/// The representation of an `eth_call` struct.
pub const EthCall = union(enum) {
    legacy: LegacyEthCall,
    london: LondonEthCall,

    pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};
/// The representation of an London hardfork `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LondonEthCall = struct {
    from: ?Address = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Address = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LegacyEthCall = struct {
    from: ?Address = null,
    gasPrice: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Address = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// Return struct for fee estimation calculation.
pub const EstimateFeeReturn = union(enum) { london: struct {
    max_priority_fee: Gwei,
    max_fee_gas: Gwei,
}, legacy: struct {
    gas_price: Gwei,
}, cancun: struct {
    max_priority_fee: Gwei,
    max_fee_gas: Gwei,
    max_fee_per_blob: Gwei,
} };
/// Provides recent fee market data that consumers can use to determine
pub const FeeHistory = struct {
    /// List of each block's base fee
    baseFeePerGas: []const u256,
    /// List of each block's base blob fee
    baseFeePerBlobGas: ?[]const u256 = null,
    /// Ratio of gas used out of the total available limit
    gasUsedRatio: []const f64,
    /// Ratio of blob gas used out of the total available limit
    blobGasUsedRation: ?[]const f64 = null,
    /// Block corresponding to first response value
    oldestBlock: u64,
    /// List every txs priority fee per block
    /// Depending on the blockCount or the newestBlock this can be null
    reward: ?[]const []const u256 = null,

    pub usingnamespace RequestParser(@This());
};
