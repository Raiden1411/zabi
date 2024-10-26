const kzg = @import("c-kzg-4844");
const log = @import("log.zig");
const meta = @import("zabi-meta");
const std = @import("std");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Blob = kzg.KZG4844.Blob;
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
const StructToTupleType = meta.utils.StructToTupleType;
const Token = std.json.Token;
const Value = std.json.Value;
const Wei = types.Wei;

/// Tuple representing an encoded envelope for the Berlin hardfork.
pub const BerlinEnvelope = StructToTupleType(BerlinTransactionEnvelope);
/// Tuple representing an encoded envelope for the Berlin hardfork with the signature.
pub const BerlinEnvelopeSigned = StructToTupleType(BerlinTransactionEnvelopeSigned);
/// Tuple representing an encoded envelope for the London hardfork.
pub const CancunEnvelope = StructToTupleType(CancunTransactionEnvelope);
/// Tuple representing an encoded envelope for the London hardfork with the signature.
pub const CancunEnvelopeSigned = StructToTupleType(CancunTransactionEnvelopeSigned);
/// Signed cancun transaction converted to wrapper with blobs, commitments and proofs.
pub const CancunSignedWrapper = Merge(StructToTupleType(CancunTransactionEnvelopeSigned), struct { []const Blob, []const KZGCommitment, []const KZGProof });
/// Cancun transaction converted to wrapper with blobs, commitments and proofs.
pub const CancunWrapper = Merge(StructToTupleType(CancunTransactionEnvelope), struct { []const Blob, []const KZGCommitment, []const KZGProof });
/// Tuple representing EIP 7702 authorization envelope tuple.
pub const Eip7702Envelope = StructToTupleType(Eip7702TransactionEnvelope);
/// Tuple representing EIP 7702 authorization envelope tuple with the signature.
pub const Eip7702EnvelopeSigned = StructToTupleType(Eip7702TransactionEnvelopeSigned);
/// Tuple representing an encoded envelope for a legacy transaction.
pub const LegacyEnvelope = StructToTupleType(Omit(LegacyTransactionEnvelope, &.{"chainId"}));
/// Tuple representing an encoded envelope for a legacy transaction with the signature.
pub const LegacyEnvelopeSigned = StructToTupleType(Omit(LegacyTransactionEnvelopeSigned, &.{"chainId"}));
/// Tuple representing an encoded envelope for the London hardfork.
pub const LondonEnvelope = StructToTupleType(LondonTransactionEnvelope);
/// Tuple representing an encoded envelope for the London hardfork with the signature.
pub const LondonEnvelopeSigned = StructToTupleType(LondonTransactionEnvelopeSigned);

/// All of the transaction types.
pub const TransactionTypes = enum(u8) {
    legacy = 0x00,
    berlin = 0x01,
    london = 0x02,
    cancun = 0x03,
    eip7702 = 0x04,
    deposit = 0x7e,
    _,
};

/// The transaction envelope that will be serialized before getting sent to the network.
pub const TransactionEnvelope = union(enum) {
    berlin: BerlinTransactionEnvelope,
    cancun: CancunTransactionEnvelope,
    eip7702: Eip7702TransactionEnvelope,
    legacy: LegacyTransactionEnvelope,
    london: LondonTransactionEnvelope,
};
/// The transaction envelope from eip7702.
pub const Eip7702TransactionEnvelope = struct {
    chainId: u64,
    nonce: u64,
    maxPriorityFeePerGas: u64,
    maxFeePerGas: u64,
    gas: u64,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    authorizationList: []const AuthorizationPayload,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Struct representing the accessList field.
pub const AccessList = struct {
    address: Address,
    storageKeys: []const Hash,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// EIP7702 authorization payload.
pub const AuthorizationPayload = struct {
    chain_id: u64,
    address: Address,
    nonce: u64,
    y_parity: u8,
    r: u256,
    s: u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Struct representing the result of create accessList
pub const AccessListResult = struct {
    accessList: []const AccessList,
    gasUsed: Gwei,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Signed transaction envelope with the signature fields
pub const TransactionEnvelopeSigned = union(enum) {
    berlin: BerlinTransactionEnvelopeSigned,
    cancun: CancunTransactionEnvelopeSigned,
    eip7702: Eip7702TransactionEnvelopeSigned,
    legacy: LegacyTransactionEnvelopeSigned,
    london: LondonTransactionEnvelopeSigned,
};
/// The transaction envelope from eip7702.
pub const Eip7702TransactionEnvelopeSigned = struct {
    chainId: u64,
    nonce: u64,
    maxPriorityFeePerGas: u64,
    maxFeePerGas: u64,
    gas: u64,
    to: ?Address = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    authorizationList: []const AuthorizationPayload,
    v: u2,
    r: u256,
    s: u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    r: u256,
    s: u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    r: u256,
    s: u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    r: u256,
    s: u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    r: ?u256,
    s: ?u256,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    authList: ?[]const AuthorizationPayload = null,
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    blobGasPrice: ?u64 = null,
    type: ?TransactionTypes = null,
    root: ?Hex = null,
    status: ?bool = null,
    deposit_nonce: ?usize = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
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
    blobGasUsedRatio: ?[]const f64 = null,
    /// Block corresponding to first response value
    oldestBlock: u64,
    /// List every txs priority fee per block
    /// Depending on the blockCount or the newestBlock this can be null
    reward: ?[]const []const u256 = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Op stack deposit transaction representation.
pub const DepositTransaction = struct {
    sourceHash: Hash,
    from: Address,
    to: ?Address,
    mint: u256,
    value: Wei,
    gas: Gwei,
    isSystemTx: bool,
    data: ?Hex,
};

/// Op stack deposit transaction representation with the signed parameters.
pub const DepositTransactionSigned = struct {
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
    sourceHash: Hex,
    mint: ?u256 = null,
    isSystemTx: ?bool = null,
    depositReceiptVersion: ?u64 = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

/// Op stack deposit data.
pub const DepositData = struct {
    mint: u256,
    value: Wei,
    gas: Gwei,
    creation: bool,
    data: ?Hex,
};

/// Op stack return type when decoding a deposit transaction from the contract.
pub const TransactionDeposited = struct {
    from: Address,
    to: Address,
    version: u256,
    opaqueData: Hex,
    logIndex: usize,
    blockHash: Hash,
};

/// Op stack deposit envelope to be serialized.
pub const DepositTransactionEnvelope = struct {
    gas: ?Gwei = null,
    mint: ?Wei = null,
    value: ?Wei = null,
    creation: bool = false,
    data: ?Hex = null,
    to: ?Address = null,
};
