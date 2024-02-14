const std = @import("std");
const meta = @import("meta.zig");
const block = @import("block.zig");
const log = @import("log.zig");
const transaction = @import("transaction.zig");

const Block = block.Block;
const Log = log.Log;
const Logs = log.Logs;
const MinedTransactions = transaction.MinedTransactions;
const MinedTransactionHashes = transaction.MinedTransactionHashes;
const PendingTransaction = transaction.PendingTransaction;
const RequestParser = meta.RequestParser;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const UnionParser = meta.UnionParser;

pub const Hex = []const u8;
pub const Gwei = u64;
pub const Wei = u256;
pub const Ether = f64;

/// Set of public rpc actions.
pub const EthereumRpcMethods = enum { eth_chainId, eth_gasPrice, eth_accounts, eth_getBalance, eth_getBlockByNumber, eth_getBlockByHash, eth_blockNumber, eth_getTransactionCount, eth_getBlockTransactionCountByHash, eth_getBlockTransactionCountByNumber, eth_getUncleCountByBlockHash, eth_getUncleCountByBlockNumber, eth_getCode, eth_getTransactionByHash, eth_getTransactionByBlockHashAndIndex, eth_getTransactionByBlockNumberAndIndex, eth_getTransactionReceipt, eth_getUncleByBlockHashAndIndex, eth_getUncleByBlockNumberAndIndex, eth_newFilter, eth_newBlockFilter, eth_newPendingTransactionFilter, eth_uninstallFilter, eth_getFilterChanges, eth_getFilterLogs, eth_getLogs, eth_sign, eth_signTransaction, eth_sendTransaction, eth_sendRawTransaction, eth_call, eth_estimateGas, eth_maxPriorityFeePerGas, eth_subscribe, eth_unsubscribe, eth_signTypedData_v4 };

/// Enum of know chains.
/// More will be added in the future.
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
/// Zig struct representation of a RPC Request
pub fn EthereumRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: EthereumRpcMethods,
        params: T,
        id: usize,
    };
}
/// Zig struct representation of a RPC Response
pub fn EthereumResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8,
        id: usize,
        result: T,

        pub usingnamespace if (@typeInfo(T) == .Int) RequestParser(@This()) else struct {};
    };
}
/// Zig struct representation of a RPC subscribe response
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
/// Zig struct representation of a RPC error message
pub const ErrorResponse = struct {
    code: EthereumErrorCodes,
    message: []const u8,
    data: ?[]const u8 = null,
};
/// Ethereum RPC error codes.
/// https://eips.ethereum.org/EIPS/eip-1474#error-codes
pub const EthereumErrorCodes = enum(isize) {
    TooManyRequests = 429,
    InvalidInput = -32000,
    ResourceNotFound = -32001,
    ResourceUnavailable = -32002,
    TransactionRejected = -32003,
    MethodNotSupported = -32004,
    LimitExceeded = -32005,
    RpcVersionNotSupported = -32006,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    ParseError = -32700,
    _,
};
/// Zig struct representation of a RPC error response
pub const EthereumErrorResponse = struct { jsonrpc: []const u8, id: usize, @"error": ErrorResponse };
/// Mostly used for requests
pub const HexRequestParameters = []const Hex;
/// Know ethereum events emited by the websocket client
pub const EthereumEvents = union(enum) {
    new_heads_event: EthereumSubscribeResponse(Block),
    pending_transactions_event: EthereumSubscribeResponse(PendingTransaction),
    pending_transactions_hashes_event: EthereumSubscribeResponse(Hex),
    log_event: EthereumSubscribeResponse(Log),
    logs_event: EthereumResponse(?Logs),
    accounts_event: EthereumResponse([]const Hex),
    receipt_event: EthereumResponse(?TransactionReceipt),
    transaction_event: EthereumResponse(?Transaction),
    bool_event: EthereumResponse(bool),
    block_event: EthereumResponse(?Block),
    hex_event: EthereumResponse(Hex),
    mined_transaction_hashes_event: EthereumSubscribeResponse(MinedTransactionHashes),
    mined_transaction_event: EthereumSubscribeResponse(MinedTransactions),
    too_many_requests: struct { message: []const u8 },

    pub usingnamespace UnionParser(@This());
};
