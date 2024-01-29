const log = @import("log.zig");
const meta = @import("meta.zig");
const std = @import("std");
const types = @import("ethereum.zig");

// All the bellow are helper tuples that are used for serialization purposes.
pub const EncodedAccessList = std.meta.Tuple(&[_]type{ types.Hex, []const types.Hex });

pub const EnvelopeEip1559 = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const EncodedAccessList });

pub const EnvelopeEip1559Signed = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const EncodedAccessList, u4, types.Hex, types.Hex });

pub const EnvelopeEip2930 = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const EncodedAccessList });

pub const EnvelopeEip2930Signed = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const EncodedAccessList, u4, types.Hex, types.Hex });

pub const EnvelopeLegacy = std.meta.Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex });

pub const EnvelopeLegacySigned = std.meta.Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, usize, types.Hex, types.Hex });

/// The transaction envelope that will be serialized before getting sent to the network.
pub const TransactionEnvelope = union(enum) {
    eip1559: TransactionEnvelopeEip1559,
    eip2930: TransactionEnvelopeEip2930,
    legacy: TransactionEnvelopeLegacy,
};

pub const TransactionEnvelopeEip1559 = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: types.Gwei,
    maxFeePerGas: types.Gwei,
    gas: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
    accessList: []const AccessList,
};

pub const TransactionEnvelopeEip2930 = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
    accessList: []const AccessList,
};

pub const TransactionEnvelopeLegacy = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
};

pub const AccessList = struct {
    address: types.Hex,
    storageKeys: []const types.Hex,

    pub usingnamespace meta.RequestParser(@This());
};

/// Signed transaction envelope types.
pub const TransactionEnvelopeSigned = union(enum) {
    eip1559: TransactionEnvelopeEip1559Signed,
    eip2930: TransactionEnvelopeEip2930Signed,
    legacy: TransactionEnvelopeLegacySigned,
};

pub const TransactionEnvelopeEip1559Signed = struct {
    type: u2 = 2,
    chainId: usize,
    nonce: u64,
    maxPriorityFeePerGas: types.Gwei,
    maxFeePerGas: types.Gwei,
    gas: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
    accessList: []const AccessList,
    r: types.Hex,
    s: types.Hex,
    v: u4,
};

pub const TransactionEnvelopeEip2930Signed = struct {
    type: u2 = 1,
    chainId: usize,
    nonce: u64,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
    accessList: []const AccessList,
    r: types.Hex,
    s: types.Hex,
    v: u4,
};

pub const TransactionEnvelopeLegacySigned = struct {
    type: u2 = 0,
    chainId: usize = 0,
    nonce: u64,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    to: ?types.Hex,
    value: types.Wei,
    data: ?types.Hex,
    r: types.Hex,
    s: types.Hex,
    v: usize,
};

/// Same as `Envelope` but were all fields are optionals.
pub const PrepareEnvelope = union(enum) {
    eip1559: PrepareEnvelopeEip1559,
    eip2930: PrepareEnvelopeEip2930,
    legacy: PrepareEnvelopeLegacy,
};

pub const PrepareEnvelopeEip1559 = struct {
    type: u2 = 2,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    maxPriorityFeePerGas: ?types.Gwei = null,
    maxFeePerGas: ?types.Gwei = null,
    gas: ?types.Gwei = null,
    to: ?types.Hex = null,
    value: ?types.Wei = null,
    data: ?types.Hex = null,
    accessList: ?[]const AccessList = null,
};

pub const PrepareEnvelopeEip2930 = struct {
    type: u2 = 1,
    chainId: ?usize = null,
    nonce: ?u64 = null,
    gas: ?types.Gwei = null,
    gasPrice: ?types.Gwei = null,
    to: ?types.Hex = null,
    value: ?types.Wei = null,
    data: ?types.Hex = null,
    accessList: ?[]const AccessList = null,
};

pub const PrepareEnvelopeLegacy = struct {
    type: u2 = 0,
    chainId: ?usize = 0,
    nonce: ?u64 = null,
    gas: ?types.Gwei = null,
    gasPrice: ?types.Gwei = null,
    to: ?types.Hex = null,
    value: ?types.Wei = null,
    data: ?types.Hex = null,
};

pub const TransactionObjectEip1559 = struct {
    hash: types.Hex,
    nonce: u64,
    blockHash: ?types.Hex,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: types.Hex,
    to: types.Hex,
    value: types.Wei,
    gasPrice: types.Gwei,
    gas: types.Gwei,
    input: types.Hex,
    v: u4,
    r: types.Hex,
    s: types.Hex,
    isSystemTx: bool,
    sourceHash: types.Hex,
    type: u2,
    accessList: []const AccessList,
    maxPriorityFeePerGas: types.Gwei,
    maxFeePerGas: types.Gwei,
    chainId: usize,
    yParity: u1,

    pub usingnamespace meta.RequestParser(@This());
};

pub const TransactionObjectEip2930 = struct {
    blockHash: ?types.Hex,
    blockNumber: ?u64,
    from: types.Hex,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    hash: types.Hex,
    input: types.Hex,
    nonce: u64,
    to: types.Hex,
    transactionIndex: ?u64,
    value: types.Wei,
    v: u8,
    r: types.Hex,
    s: types.Hex,
    type: u4,
    accessList: []const AccessList,
    chainId: usize,
    isSystemTx: bool,
    sourceHash: types.Hex,

    pub usingnamespace meta.RequestParser(@This());
};

pub const TransactionObjectLegacy = struct {
    blockHash: ?types.Hex,
    blockNumber: ?u64,
    from: types.Hex,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    hash: types.Hex,
    input: types.Hex,
    nonce: u64,
    to: types.Hex,
    transactionIndex: ?u64,
    value: types.Wei,
    v: usize,
    r: types.Hex,
    s: types.Hex,
    type: u2,
    isSystemTx: bool,
    sourceHash: types.Hex,

    pub usingnamespace meta.RequestParser(@This());
};

pub const UntypedTransactionObject = struct {
    blockHash: ?types.Hex,
    blockNumber: ?u64,
    from: types.Hex,
    gas: types.Gwei,
    gasPrice: types.Gwei,
    hash: types.Hex,
    input: types.Hex,
    nonce: u64,
    to: types.Hex,
    transactionIndex: ?u64,
    value: types.Wei,
    v: usize,
    r: types.Hex,
    s: types.Hex,
    isSystemTx: bool,
    sourceHash: types.Hex,

    pub usingnamespace meta.RequestParser(@This());
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

    pub usingnamespace meta.UnionParser(@This());
};

pub const TransactionReceipt = struct {
    transactionHash: types.Hex,
    transactionIndex: usize,
    blockHash: types.Hex,
    blockNumber: u64,
    from: types.Hex,
    to: ?types.Hex,
    cumulativeGasUsed: types.Gwei,
    effectiveGasPrice: types.Gwei,
    gasUsed: types.Gwei,
    contractAddress: ?types.Hex,
    logs: log.Logs,
    logsBloom: types.Hex,
    type: u2,
    root: ?types.Hex,
    status: ?bool,
    deposit_nonce: ?usize,

    pub usingnamespace meta.RequestParser(@This());
};

pub const EthCall = union(enum) {
    eip1559: EthCallEip1559,
    legacy: EthCallLegacy,

    pub usingnamespace meta.UnionParser(@This());
};

pub const EthCallEip1559 = struct {
    from: ?types.Hex = null,
    maxPriorityFeePerGas: ?types.Gwei = null,
    maxFeePerGas: ?types.Gwei = null,
    gas: ?types.Gwei = null,
    to: ?types.Hex = null,
    value: ?types.Wei = null,
    data: ?types.Hex = null,

    pub usingnamespace meta.RequestParser(@This());
};

pub const EthCallLegacy = struct {
    from: ?types.Hex = null,
    gasPrice: ?types.Gwei = null,
    gas: ?types.Gwei = null,
    to: ?types.Hex = null,
    value: ?types.Wei = null,
    data: ?types.Hex = null,

    pub usingnamespace meta.RequestParser(@This());
};

/// This is used for eth call request and want to send the request with all hexed values.
/// The JSON RPC cannot understand the "native" value so we need these helper types.
pub const EthCallHexed = union(enum) {
    eip1559: EthCallEip1559Hexed,
    legacy: EthCallLegacyHexed,

    pub usingnamespace meta.UnionParser(@This());
};

pub const EthCallEip1559Hexed = struct {
    from: ?types.Hex = null,
    maxPriorityFeePerGas: ?types.Hex = null,
    maxFeePerGas: ?types.Hex = null,
    gas: ?types.Hex = null,
    to: ?types.Hex = null,
    value: ?types.Hex = null,
    data: ?types.Hex = null,

    pub usingnamespace meta.RequestParser(@This());
};

pub const EthCallLegacyHexed = struct {
    from: ?types.Hex = null,
    gasPrice: ?types.Hex = null,
    gas: ?types.Hex = null,
    to: ?types.Hex = null,
    value: ?types.Hex = null,
    data: ?types.Hex = null,

    pub usingnamespace meta.RequestParser(@This());
};

/// Return struct for fee estimation calculation.
pub const EstimateFeeReturn = union(enum) { eip1559: struct {
    max_priority_fee: types.Gwei,
    max_fee_gas: types.Gwei,
}, legacy: struct {
    gas_price: types.Gwei,
} };
