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

/// Tuple representig an encoded accessList
pub const EncodedAccessList = std.meta.Tuple(&[_]type{ Hex, []const Hex });
/// Tuple representig an encoded envelope for the London hardfork
pub const EnvelopeEip1559 = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList });
/// Tuple representig an encoded envelope for the London hardfork with the signature
pub const EnvelopeEip1559Signed = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u4, Hex, Hex });
/// Tuple representig an encoded envelope for the Berlin hardfork
pub const EnvelopeEip2930 = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList });
/// Tuple representig an encoded envelope for the Berlin hardfork with the signature
pub const EnvelopeEip2930Signed = std.meta.Tuple(&[_]type{ usize, u64, Gwei, Gwei, ?Hex, Wei, ?Hex, []const EncodedAccessList, u4, Hex, Hex });
/// Tuple representig an encoded envelope for a legacy transaction
pub const EnvelopeLegacy = std.meta.Tuple(&[_]type{ u64, Gwei, Gwei, ?Hex, Wei, ?Hex });
/// Tuple representig an encoded envelope for a legacy transaction
pub const EnvelopeLegacySigned = std.meta.Tuple(&[_]type{ u64, Gwei, Gwei, ?Hex, Wei, ?Hex, usize, Hex, Hex });
/// Some nodes represent pending transactions hashes like this.
pub const MinedTransactionHashes = struct {
    removed: bool,
    transaction: struct { hash: Hex },
};
/// Pending transactions objects represented via the subscription responses.
pub const MinedTransactions = struct {
    removed: bool,
    transaction: PendingTransaction,
};
/// The transaction envelope that will be serialized before getting sent to the network.
pub const TransactionEnvelope = union(enum) {
    eip1559: TransactionEnvelopeEip1559,
    eip2930: TransactionEnvelopeEip2930,
    legacy: TransactionEnvelopeLegacy,
};
/// The transaction envelope from the London hardfork
pub const TransactionEnvelopeEip1559 = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork
pub const TransactionEnvelopeEip2930 = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,
    accessList: []const AccessList,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction
pub const TransactionEnvelopeLegacy = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,

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
    eip1559: TransactionEnvelopeEip1559Signed,
    eip2930: TransactionEnvelopeEip2930Signed,
    legacy: TransactionEnvelopeLegacySigned,

    pub usingnamespace UnionParser(@This());
};
/// The transaction envelope from the London hardfork with the signature fields
pub const TransactionEnvelopeEip1559Signed = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: Gwei,
    maxFeePerGas: Gwei,
    gas: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,
    accessList: []const AccessList,
    r: Hex,
    s: Hex,
    v: u4,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from the Berlin hardfork with the signature fields
pub const TransactionEnvelopeEip2930Signed = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,
    accessList: []const AccessList,
    r: Hex,
    s: Hex,
    v: u4,

    pub usingnamespace RequestParser(@This());
};
/// The transaction envelope from a legacy transaction with the signature fields
pub const TransactionEnvelopeLegacySigned = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: Gwei,
    gasPrice: Gwei,
    to: ?Hex,
    value: Wei,
    data: ?Hex,
    r: Hex,
    s: Hex,
    v: usize,

    pub usingnamespace RequestParser(@This());
};
/// Same as `Envelope` but were all fields are optionals.
pub const PrepareEnvelope = union(enum) {
    eip1559: PrepareEnvelopeEip1559,
    eip2930: PrepareEnvelopeEip2930,
    legacy: PrepareEnvelopeLegacy,

    pub usingnamespace UnionParser(@This());
};
/// The transaction envelope from the London hardfork where all fields are optionals
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const PrepareEnvelopeEip1559 = struct {
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
pub const PrepareEnvelopeEip2930 = struct {
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
pub const PrepareEnvelopeLegacy = struct {
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
pub const PendingTransactionEip1559 = struct {
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
pub const PendingTransactionLegacy = struct {
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
    eip1559: PendingTransactionEip1559,
    legacy: PrepareEnvelopeLegacy,

    pub usingnamespace UnionParser(@This());
};
/// The London hardfork representation of a transaction.
pub const TransactionObjectEip1559 = struct {
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
    yParity: u1,

    pub usingnamespace RequestParser(@This());
};
/// The Berlin hardfork representation of a transaction.
pub const TransactionObjectEip2930 = struct {
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
pub const TransactionObjectLegacy = struct {
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
pub const UntypedTransactionObject = struct {
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
    untyped: UntypedTransactionObject,
    /// Legacy type transactions.
    legacy: TransactionObjectLegacy,
    /// Legacy type transactions that might have the accessList.
    eip2930: TransactionObjectEip2930,
    /// Current transaction objects.
    eip1559: TransactionObjectEip1559,

    pub usingnamespace UnionParser(@This());
};
/// The transaction receipt representation
pub const TransactionReceipt = struct {
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
    root: ?Hex,
    status: ?bool,
    deposit_nonce: ?usize,

    pub usingnamespace RequestParser(@This());
};
/// The representation of an `eth_call` struct.
pub const EthCall = union(enum) {
    eip1559: EthCallEip1559,
    legacy: EthCallLegacy,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an London hardfork `eth_call` struct where all fields are optional
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const EthCallEip1559 = struct {
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
pub const EthCallLegacy = struct {
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
    eip1559: EthCallEip1559Hexed,
    legacy: EthCallLegacyHexed,

    pub usingnamespace UnionParser(@This());
};
/// The representation of an London hardfork `eth_call` struct where all fields are optional and hex values.
/// These are optionals so that when we stringify we can
/// use the option `ignore_null_fields`
pub const EthCallEip1559Hexed = struct {
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
pub const EthCallLegacyHexed = struct {
    from: ?Hex = null,
    gasPrice: ?Hex = null,
    gas: ?Hex = null,
    to: ?Hex = null,
    value: ?Hex = null,
    data: ?Hex = null,

    pub usingnamespace RequestParser(@This());
};
/// Return struct for fee estimation calculation.
pub const EstimateFeeReturn = union(enum) { eip1559: struct {
    max_priority_fee: Gwei,
    max_fee_gas: Gwei,
}, legacy: struct {
    gas_price: Gwei,
} };
