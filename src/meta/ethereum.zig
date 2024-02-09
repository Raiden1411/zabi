const std = @import("std");
const meta = @import("meta.zig");
const block = @import("block.zig");
const log = @import("log.zig");
const transaction = @import("transaction.zig");

pub const Hex = []const u8;
pub const Gwei = u64;
pub const Wei = u256;
pub const Ether = f64;

/// Set of public rpc actions.
pub const EthereumRpcMethods = enum { eth_chainId, eth_gasPrice, eth_accounts, eth_getBalance, eth_getBlockByNumber, eth_getBlockByHash, eth_blockNumber, eth_getTransactionCount, eth_getBlockTransactionCountByHash, eth_getBlockTransactionCountByNumber, eth_getUncleCountByBlockHash, eth_getUncleCountByBlockNumber, eth_getCode, eth_getTransactionByHash, eth_getTransactionByBlockHashAndIndex, eth_getTransactionByBlockNumberAndIndex, eth_getTransactionReceipt, eth_getUncleByBlockHashAndIndex, eth_getUncleByBlockNumberAndIndex, eth_newFilter, eth_newBlockFilter, eth_newPendingTransactionFilter, eth_uninstallFilter, eth_getFilterChanges, eth_getFilterLogs, eth_getLogs, eth_sign, eth_signTransaction, eth_sendTransaction, eth_sendRawTransaction, eth_call, eth_estimateGas, eth_maxPriorityFeePerGas, eth_subscribe, eth_unsubscribe, eth_signTypedData_v4 };

pub const PublicChains = enum(usize) {
    ethereum = 1,
    goerli = 5,
    op_mainnet = 10,
    cronos = 25,
    bnb = 56,
    ethereum_classic = 61,
    op_kovan = 69,
    gnosis = 100,
    polygon = 137,
    fantom = 250,
    boba = 288,
    op_goerli = 420,
    base = 8543,
    anvil = 31337,
    arbitrum = 42161,
    arbitrum_nova = 42170,
    celo = 42220,
    avalanche = 43114,
};

pub fn EthereumRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: EthereumRpcMethods,
        params: T,
        id: usize,
    };
}

pub fn EthereumResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8,
        id: usize,
        result: T,

        pub usingnamespace if (@typeInfo(T) == .Int) meta.RequestParser(@This()) else struct {};
    };
}

pub fn EthereumSubscribeResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8,
        method: []const u8,
        params: struct {
            result: T,
            subscription: Hex,
        },
    };
}

pub const ErrorResponse = struct {
    code: isize,
    message: []const u8,
    data: ?[]const u8 = null,
};

pub const EthereumErrorResponse = struct { jsonrpc: []const u8, id: usize, @"error": ErrorResponse };

pub const HexRequestParameters = []const Hex;

pub const EthereumEvents = union(enum) {
    new_heads_event: EthereumSubscribeResponse(block.Block),
    pending_transactions_event: EthereumSubscribeResponse(transaction.PendingTransaction),
    pending_transactions_hashes_event: EthereumSubscribeResponse([]const u8),
    log_event: EthereumSubscribeResponse(log.Log),
    logs_event: EthereumResponse(log.Logs),
    accounts_event: EthereumResponse([]const []const u8),
    receipt_event: EthereumResponse(transaction.TransactionReceipt),
    transaction_event: EthereumResponse(transaction.Transaction),
    bool_event: EthereumResponse(bool),
    block_event: EthereumResponse(block.Block),
    hex_event: EthereumResponse([]const u8),
    mined_transaction_hashes_event: EthereumSubscribeResponse(transaction.MinedTransactionHashes),
    mined_transaction_event: EthereumSubscribeResponse(transaction.MinedTransactions),

    pub usingnamespace meta.UnionParser(@This());
};
