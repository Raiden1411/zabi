const meta = @import("meta/meta.zig");
const types = @import("meta/types.zig");

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
