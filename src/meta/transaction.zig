const log = @import("log.zig");
const meta = @import("meta.zig");
const std = @import("std");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const Logs = log.Logs;
const Omit = meta.Omit;
const RequestParser = meta.RequestParser;
const StructToTupleType = meta.StructToTupleType;
const Wei = types.Wei;
const UnionParser = meta.UnionParser;

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
// /// Signed cancun transaction converted to wrapper with blobs, commitments and proofs
// pub const CancunSignedWrapper = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex, u4, Hex, Hex, []const Hex, []const Hex, []const Hex });
// /// Cancun transaction converted to wrapper with blobs, commitments and proofs
// pub const CancunWrapper = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex, []const Hex, []const Hex, []const Hex });

/// Some nodes represent pending transactions hashes like this.
pub const PendingTransactionHashesSubscription = struct {
    removed: bool,
    transaction: struct { hash: Hash },

    pub usingnamespace RequestParser(@This());
};
/// Pending transactions objects represented via the subscription responses.
pub const PendingTransactionsSubscription = struct {
    removed: bool,
    transaction: PendingTransaction,
};
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
/// Signed transaction envelope with the signature fields
pub const TransactionEnvelopeSigned = union(enum) {
    berlin: BerlinTransactionEnvelopeSigned,
    cancun: CancunTransactionEnvelopeSigned,
    legacy: LegacyTransactionEnvelopeSigned,
    london: LondonTransactionEnvelopeSigned,

    pub usingnamespace UnionParser(@This());
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
    r: Hash,
    s: Hash,

    pub usingnamespace RequestParser(@This());
};
/// Same as `Envelope` but were all fields are optionals.
pub const UnpreparedTransactionEnvelope = struct {
    type: u2,
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
/// The legacy representation of a London hardfork transaction.
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
    r: Hash,
    s: Hash,
    type: u2,
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
    v: u4,
    r: Hash,
    s: Hash,
    type: u2,
    chainId: usize,

    pub usingnamespace RequestParser(@This());
};
/// Pending transaction from a subscription event
pub const PendingTransaction = union(enum) {
    london: LondonPendingTransaction,
    legacy: LegacyPendingTransaction,

    pub usingnamespace UnionParser(@This());
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
    r: Hash,
    s: Hash,
    isSystemTx: bool,
    sourceHash: Hash,
    type: u2,
    accessList: []const AccessList,
    blobVersionedHashes: []const Hash,
    maxFeePerBlobGas: Gwei,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    // yParity: u1,

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
    r: Hash,
    s: Hash,
    isSystemTx: bool,
    sourceHash: Hash,
    type: u2,
    accessList: []const AccessList,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    // yParity: u1,

    pub usingnamespace RequestParser(@This());
};
/// The Berlin hardfork representation of a transaction.
pub const BerlinTransaction = struct {
    blockHash: ?Hash,
    blockNumber: ?u64,
    from: Address,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hash,
    input: Hex,
    nonce: u64,
    to: ?Address,
    transactionIndex: ?u64,
    value: Wei,
    v: u8,
    r: Hash,
    s: Hash,
    type: u4,
    accessList: []const AccessList,
    chainId: usize,
    isSystemTx: bool,
    sourceHash: Hash,

    pub usingnamespace RequestParser(@This());
};
/// The legacy representation of a transaction.
pub const LegacyTransaction = struct {
    blockHash: ?Hash,
    blockNumber: ?u64,
    from: Address,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hash,
    input: Hex,
    nonce: u64,
    to: ?Address,
    transactionIndex: ?u64,
    value: Wei,
    v: usize,
    r: Hash,
    s: Hash,
    type: u2,
    isSystemTx: bool,
    sourceHash: Hash,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an untyped transaction.
pub const UntypedTransaction = struct {
    blockHash: ?Hash,
    blockNumber: ?u64,
    from: Address,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hash,
    input: Hex,
    nonce: u64,
    to: ?Address,
    transactionIndex: ?u64,
    value: Wei,
    v: usize,
    r: Hash,
    s: Hash,
    isSystemTx: bool,
    sourceHash: Hash,

    pub usingnamespace RequestParser(@This());
};
/// All transactions objects that one might find whilest interaction
/// with the JSON RPC server.
pub const Transaction = union(enum) {
    /// Some transactions might not have the type field.
    untyped: UntypedTransaction,
    /// Legacy type transactions.
    legacy: LegacyTransaction,
    /// Berlin hardfork transactions that might have the accessList.
    berlin: BerlinTransaction,
    /// London hardfork transaction objects.
    london: LondonTransaction,
    /// Cancun hardfork transactions.
    cancun: CancunTransaction,

    pub usingnamespace UnionParser(@This());
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
    type: u2,
    root: ?Hex = null,
    status: ?bool,
    deposit_nonce: ?usize,

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
    type: u2,
    status: ?bool,
    deposit_nonce: ?u64,

    pub usingnamespace RequestParser(@This());
};
/// All possible transaction receipts
pub const TransactionReceipt = union(enum) {
    legacy: LegacyReceipt,
    cancun: CancunReceipt,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an `eth_call` struct.
pub const EthCall = union(enum) {
    legacy: LegacyEthCall,
    london: LondonEthCall,

    pub usingnamespace UnionParser(@This());
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
