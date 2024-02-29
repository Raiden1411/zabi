const log = @import("log.zig");
const meta = @import("meta.zig");
const std = @import("std");
const types = @import("ethereum.zig");

// Types
const Gwei = types.Gwei;
const Hex = types.Hex;
const Logs = log.Logs;
const RequestParser = meta.RequestParser;
const Wei = types.Wei;
const UnionParser = meta.UnionParser;

/// Tuple representig an encoded envelope for the Berlin hardfork
pub const BerlinEnvelope = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList });
/// Tuple representig an encoded envelope for the Berlin hardfork with the signature
pub const BerlinEnvelopeSigned = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u4, Hex, Hex });
/// Tuple representig an encoded accessList
pub const EncodedAccessList = std.meta.Tuple(&[_]type{ Hex, []const Hex });
/// Tuple representig an encoded envelope for a legacy transaction
pub const LegacyEnvelope = std.meta.Tuple(&[_]type{ u64, Gwei, Gwei, ?Hex, Wei, ?Hex });
/// Tuple representig an encoded envelope for a legacy transaction
pub const LegacyEnvelopeSigned = std.meta.Tuple(&[_]type{ u64, Gwei, Gwei, ?Hex, Wei, ?Hex, usize, Hex, Hex });
/// Tuple representig an encoded envelope for the London hardfork
pub const LondonEnvelope = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList });
/// Tuple representig an encoded envelope for the London hardfork with the signature
pub const LondonEnvelopeSigned = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u4, Hex, Hex });
/// Tuple representig an encoded envelope for the London hardfork
pub const CancunEnvelope = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex });
/// Tuple representig an encoded envelope for the London hardfork with the signature
pub const CancunEnvelopeSigned = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex, u4, Hex, Hex });
/// Signed cancun transaction converted to wrapper with blobs, commitments and proofs
pub const CancunSignedWrapper = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex, u4, Hex, Hex, []const Hex, []const Hex, []const Hex });
/// Cancun transaction converted to wrapper with blobs, commitments and proofs
pub const CancunWrapper = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u64, []const Hex, []const Hex, []const Hex, []const Hex });
/// Some nodes represent pending transactions hashes like this.
pub const PendingTransactionHashesSubscription = struct {
    removed: bool,
    transaction: struct { hash: Hex },
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
    type: u2 = 3,
    chainId: usize,
    nonce: u64,
    maxFeePerBlobGas: Gwei,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    blobVersionedHashes: ?[]const Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the London hardfork
pub const LondonTransactionEnvelope = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork
pub const BerlinTransactionEnvelope = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction
pub const LegacyTransactionEnvelope = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// Struct representing the accessList field.
pub const AccessList = struct {
    address: Hex,
    storageKeys: []const Hex,

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
    type: u2 = 3,
    chainId: usize,
    nonce: u64,
    maxFeePerBlobGas: Gwei,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    blobVersionedHashes: ?[]const Hex = null,
    r: Hex,
    s: Hex,
    v: u4,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the London hardfork with the signature fields
pub const LondonTransactionEnvelopeSigned = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    r: Hex,
    s: Hex,
    v: u4,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork with the signature fields
pub const BerlinTransactionEnvelopeSigned = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    accessList: []const AccessList,
    r: Hex,
    s: Hex,
    v: u4,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction with the signature fields
pub const LegacyTransactionEnvelopeSigned = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex = null,
    value: Wei,
    data: ?Hex = null,
    r: Hex,
    s: Hex,
    v: usize,

    pub usingnamespace RequestParser(@This());
};
/// Same as `Envelope` but were all fields are optionals.
pub const PrepareEnvelope = union(enum) {
    berlin: PrepareBerlinEnvelope,
    cancun: PrepareCancunEnvelope,
    legacy: PrepareLegacyEnvelope,
    london: PrepareLondonEnvelope,

    pub usingnamespace UnionParser(@This());
};
/// The transaction envelope from the London hardfork where all fields are optionals
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const PrepareCancunEnvelope = struct {
    type: u2 = 3,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    maxFeePerBlobGas: ?Gwei = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,
    accessList: ?[]const AccessList = null,
    blobVersionedHashes: ?[]const Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the London hardfork where all fields are optionals
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const PrepareLondonEnvelope = struct {
    type: u2 = 2,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,
    accessList: ?[]const AccessList = null,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork where all fields are optionals
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const PrepareBerlinEnvelope = struct {
    type: u2 = 1,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    gas: ?Gwei = null,
    gasPrice: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,
    accessList: ?[]const AccessList = null,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction where all fields are optionals
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const PrepareLegacyEnvelope = struct {
    type: u2 = 0,
    chainId: ?usize = 0,
    nonce: ?u64 = null,
    gas: ?Gwei = null,
    gasPrice: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The legacy representation of a London hardfork transaction.
pub const LondonPendingTransaction = struct {
    hash: Hex,
    nonce: u64,
    blockHash: ?Hex,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Hex,
    to: ?Hex,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    r: Hex,
    s: Hex,
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
    hash: Hex,
    nonce: u64,
    blockHash: ?Hex,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Hex,
    to: ?Hex,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    r: Hex,
    s: Hex,
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
    hash: Hex,
    nonce: u64,
    blockHash: ?Hex,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Hex,
    to: ?Hex,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    r: Hex,
    s: Hex,
    isSystemTx: bool,
    sourceHash: Hex,
    type: u2,
    accessList: []const AccessList,
    blobVersionedHashes: []const Hex,
    maxFeePerBlobGas: Gwei,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    chainId: usize,
    // yParity: u1,

    pub usingnamespace RequestParser(@This());
};
/// The London hardfork representation of a transaction.
pub const LondonTransaction = struct {
    hash: Hex,
    nonce: u64,
    blockHash: ?Hex,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Hex,
    to: ?Hex,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: u4,
    r: Hex,
    s: Hex,
    isSystemTx: bool,
    sourceHash: Hex,
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
    blockHash: ?Hex,
    blockNumber: ?u64,
    from: Hex,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hex,
    input: Hex,
    nonce: u64,
    to: ?Hex,
    transactionIndex: ?u64,
    value: Wei,
    v: u8,
    r: Hex,
    s: Hex,
    type: u4,
    accessList: []const AccessList,
    chainId: usize,
    isSystemTx: bool,
    sourceHash: Hex,

    pub usingnamespace RequestParser(@This());
};
/// The legacy representation of a transaction.
pub const LegacyTransaction = struct {
    blockHash: ?Hex,
    blockNumber: ?u64,
    from: Hex,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hex,
    input: Hex,
    nonce: u64,
    to: ?Hex,
    transactionIndex: ?u64,
    value: Wei,
    v: usize,
    r: Hex,
    s: Hex,
    type: u2,
    isSystemTx: bool,
    sourceHash: Hex,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an untyped transaction.
pub const UntypedTransaction = struct {
    blockHash: ?Hex,
    blockNumber: ?u64,
    from: Hex,
    gas: Gwei,
    gasPrice: Gwei,
    hash: Hex,
    input: Hex,
    nonce: u64,
    to: ?Hex,
    transactionIndex: ?u64,
    value: Wei,
    v: usize,
    r: Hex,
    s: Hex,
    isSystemTx: bool,
    sourceHash: Hex,

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
pub const LondonReceipt = struct {
    transactionHash: Hex,
    transactionIndex: usize,
    blockHash: Hex,
    blockNumber: ?u64,
    from: Hex,
    to: ?Hex,
    cumulativeGasUsed: Gwei,
    effectiveGasPrice: Gwei,
    gasUsed: Gwei,
    contractAddress: ?Hex,
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
    transactionHash: Hex,
    transactionIndex: usize,
    blockHash: Hex,
    blockNumber: ?u64,
    from: Hex,
    to: ?Hex,
    cumulativeGasUsed: Gwei,
    effectiveGasPrice: Gwei,
    blobGasPrice: Gwei,
    blobGasUsed: Gwei,
    gasUsed: Gwei,
    contractAddress: ?Hex,
    logs: Logs,
    logsBloom: Hex,
    type: u2,
    root: ?Hex = null,
    status: ?bool,
    deposit_nonce: ?usize,

    pub usingnamespace RequestParser(@This());
};
/// All possible transaction receipts
pub const TransactionReceipt = union(enum) {
    london: LondonReceipt,
    cancun: CancunReceipt,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an `eth_call` struct.
pub const EthCall = union(enum) {
    cancun: CancunEthCall,
    legacy: LegacyEthCall,
    london: LondonEthCall,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an Cancun hardfork `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const CancunEthCall = struct {
    from: ?Hex = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an London hardfork `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LondonEthCall = struct {
    from: ?Hex = null,
    maxPriorityFeePerGas: ?Gwei = null,
    maxFeePerGas: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LegacyEthCall = struct {
    from: ?Hex = null,
    gasPrice: ?Gwei = null,
    gas: ?Gwei = null,
    to: ?Hex = null,
    value: ?Wei = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// This is used for eth call request and want to send the request with all hexed values.
/// The JSON RPC cannot understand the "native" value so we need these helper
pub const EthCallHexed = union(enum) {
    cancun: CancunEthCallHexed,
    legacy: LegacyEthCallHexed,
    london: LondonEthCallHexed,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an Cancun hardfork `eth_call` struct where all fields are optional and hex values.
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const CancunEthCallHexed = struct {
    from: ?Hex = null,
    maxPriorityFeePerGas: ?Hex = null,
    maxFeePerGas: ?Hex = null,
    gas: ?Hex = null,
    to: ?Hex = null,
    value: ?Hex = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an London hardfork `eth_call` struct where all fields are optional and hex values.
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LondonEthCallHexed = struct {
    from: ?Hex = null,
    maxPriorityFeePerGas: ?Hex = null,
    maxFeePerGas: ?Hex = null,
    gas: ?Hex = null,
    to: ?Hex = null,
    value: ?Hex = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an legacy `eth_call` struct where all fields are optional and hex values.
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const LegacyEthCallHexed = struct {
    from: ?Hex = null,
    gasPrice: ?Hex = null,
    gas: ?Hex = null,
    to: ?Hex = null,
    value: ?Hex = null,
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
