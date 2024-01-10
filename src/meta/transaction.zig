const log = @import("log.zig");
const meta = @import("meta.zig");
const types = @import("ethereum.zig");

pub const TransactionObjectEip1559 = struct {
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
    isSystemTx: bool,
    type: u2,
    accessList: []const types.Hex,
    sourceHash: types.Hex,
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
    accessList: []const types.Hex,
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
