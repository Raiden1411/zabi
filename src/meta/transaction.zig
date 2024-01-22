const log = @import("log.zig");
const meta = @import("meta.zig");
const std = @import("std");
const types = @import("ethereum.zig");

pub const EnvelopeEip1559 = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const std.meta.Tuple(&[_]type{ types.Hex, []const types.Hex }) });

pub const EnvelopeEip1559Signed = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const std.meta.Tuple(&[_]type{ types.Hex, []const types.Hex }), u2, types.Hex, types.Hex });

pub const EnvelopeEip2930 = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const std.meta.Tuple(&[_]type{ types.Hex, []const types.Hex }) });

pub const EnvelopeEip2930Signed = std.meta.Tuple(&[_]type{ usize, u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, []const std.meta.Tuple(&[_]type{ types.Hex, []const types.Hex }), u2, types.Hex, types.Hex });

pub const EnvelopeLegacy = std.meta.Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex });

pub const EnvelopeLegacySigned = std.meta.Tuple(&[_]type{ u64, types.Gwei, types.Gwei, ?types.Hex, types.Wei, ?types.Hex, usize, types.Hex, types.Hex });

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

pub const PrepareEnvelope = union(enum) {
    eip1559: PrepareEnvelopeEip1559,
    eip2930: PrepareEnvelopeEip2930,
    legacy: PrepareEnvelopeLegacy,
};

pub const PrepareEnvelopeEip1559 = meta.ToOptionalStructAndUnionMembers(TransactionObjectEip1559);
pub const PrepareEnvelopeEip2930 = meta.ToOptionalStructAndUnionMembers(TransactionObjectEip2930);
pub const PrepareEnvelopeLegacy = meta.ToOptionalStructAndUnionMembers(TransactionEnvelopeLegacy);

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
    v: u8,
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
    v: u8,
    r: types.Hex,
    s: types.Hex,
    type: u2,

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
    type: u2,
    accessList: []const AccessList,
    chainId: usize,
    yParity: u1,

    pub usingnamespace meta.RequestParser(@This());
};

pub const Transaction = union(enum) {
    legacy: TransactionObjectLegacy,
    eip2930: TransactionObjectEip2930,
    eip1559: TransactionObjectEip1559,

    pub usingnamespace meta.UnionParser(@This());
};

pub const TransactionReceiptMerge = struct {
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
    deposit_nonce: ?usize,
    status: ?bool,

    pub usingnamespace meta.RequestParser(@This());
};

pub const TransactionReceiptUntilMerge = struct {
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
    status: ?bool,

    pub usingnamespace meta.RequestParser(@This());
};

pub const TransactionReceiptPreByzantium = struct {
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

    pub usingnamespace meta.RequestParser(@This());
};

pub const TransactionReceipt = union(enum) {
    merge: TransactionReceiptMerge,
    until_merge: TransactionReceiptUntilMerge,
    pre_byzantium: TransactionReceiptPreByzantium,

    pub usingnamespace meta.UnionParser(@This());
};

pub const EthCallEip1559 = struct {
    from: ?types.Hex,
    maxPriorityFeePerGas: ?types.Gwei,
    maxFeePerGas: ?types.Gwei,
    gas: ?types.Gwei,
    to: ?types.Hex,
    value: ?types.Wei,
    data: ?types.Hex,

    pub usingnamespace meta.RequestParser(@This());
};

pub const EthCallLegacy = struct {
    from: ?types.Hex,
    gasPrice: ?types.Gwei,
    gas: ?types.Gwei,
    to: ?types.Hex,
    value: ?types.Wei,
    data: ?types.Hex,

    pub usingnamespace meta.RequestParser(@This());
};

pub const EthCall = struct {
    eip1559: EthCallEip1559,
    legacy: EthCallLegacy,

    pub usingnamespace meta.UnionParser(@This());
};

pub const EstimateFeeReturn = union(enum) { eip1559: struct {
    max_priority_fee: types.Gwei,
    max_fee_gas: types.Gwei,
}, legacy: struct {
    gas_price: types.Gwei,
} };
