const block = @import("block.zig");
const log = @import("log.zig");
const meta = @import("../meta/root.zig");
const proof = @import("proof.zig");
const std = @import("std");
const sync = @import("syncing.zig");
const transaction = @import("transaction.zig");

const AccessListResult = transaction.AccessListResult;
const ArenaAllocator = std.heap.ArenaAllocator;
const Block = block.Block;
const FeeHistory = transaction.FeeHistory;
const Log = log.Log;
const Logs = log.Logs;
const PendingTransactionsSubscription = transaction.PendingTransactionsSubscription;
const PendingTransactionHashesSubscription = transaction.PendingTransactionHashesSubscription;
const PendingTransaction = transaction.PendingTransaction;
const ProofResult = proof.ProofResult;
const RequestParser = meta.json.RequestParser;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const UnionParser = meta.json.UnionParser;

pub const Hex = []u8;
pub const Gwei = u64;
pub const Wei = u256;
pub const Hash = [32]u8;
pub const Address = [20]u8;

pub const WebsocketSubscriptions = enum {
    newHeads,
    logs,
    newPendingTransactions,
};

/// Set of public rpc actions.
pub const EthereumRpcMethods = enum {
    web3_clientVersion,
    web3_sha3,
    net_version,
    net_listening,
    net_peerCount,
    eth_chainId,
    eth_gasPrice,
    eth_accounts,
    eth_getBalance,
    eth_getBlockByNumber,
    eth_getBlockByHash,
    eth_blockNumber,
    eth_getTransactionCount,
    eth_getBlockTransactionCountByHash,
    eth_getBlockTransactionCountByNumber,
    eth_getUncleCountByBlockHash,
    eth_getUncleCountByBlockNumber,
    eth_getCode,
    eth_getTransactionByHash,
    eth_getTransactionByBlockHashAndIndex,
    eth_getTransactionByBlockNumberAndIndex,
    eth_getTransactionReceipt,
    eth_getUncleByBlockHashAndIndex,
    eth_getUncleByBlockNumberAndIndex,
    eth_newFilter,
    eth_newBlockFilter,
    eth_newPendingTransactionFilter,
    eth_uninstallFilter,
    eth_getFilterChanges,
    eth_getFilterLogs,
    eth_getLogs,
    eth_sign,
    eth_signTransaction,
    eth_sendTransaction,
    eth_sendRawTransaction,
    eth_call,
    eth_estimateGas,
    eth_maxPriorityFeePerGas,
    eth_subscribe,
    eth_unsubscribe,
    eth_signTypedData_v4,
    eth_blobBaseFee,
    eth_createAccessList,
    eth_feeHistory,
    eth_getStorageAt,
    eth_getProof,
    eth_protocolVersion,
    eth_syncing,
    eth_getRawTransactionByHash,
};

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
    zora = 7777777,
    sepolia = 11155111,
    op_sepolia = 11155420,
};
/// Wrapper around std.json.Parsed(T). Response for any of the RPC clients
pub fn RPCResponse(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        response: T,

        pub fn deinit(self: @This()) void {
            const child_allocator = self.arena.child_allocator;

            self.arena.deinit();

            child_allocator.destroy(self.arena);
        }

        pub fn fromJson(arena: *ArenaAllocator, value: T) @This() {
            return .{
                .arena = arena,
                .response = value,
            };
        }
    };
}
/// Zig struct representation of a RPC Request
pub fn EthereumRequest(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: EthereumRpcMethods,
        params: T,
        id: usize,

        pub usingnamespace RequestParser(@This());
    };
}
pub fn EthereumResponse(comptime T: type) type {
    return union(enum) {
        success: EthereumRpcResponse(T),
        @"error": EthereumErrorResponse,

        pub usingnamespace UnionParser(@This());
    };
}
/// Zig struct representation of a RPC Response
pub fn EthereumRpcResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: ?usize = null,
        result: T,

        pub usingnamespace RequestParser(@This());
    };
}
/// Zig struct representation of a RPC subscribe response
pub fn EthereumSubscribeResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: struct {
            result: T,
            subscription: u128,

            pub usingnamespace RequestParser(@This());
        },

        pub usingnamespace RequestParser(@This());
    };
}
/// Zig struct representation of a RPC error message
pub const ErrorResponse = struct {
    code: EthereumErrorCodes,
    message: []const u8,
    data: ?[]const u8 = null,

    pub usingnamespace RequestParser(@This());
};
/// Zig struct representation of a contract error response
pub const ContractErrorResponse = struct { code: EthereumErrorCodes, message: []const u8, data: []const u8 };
/// Ethereum RPC error codes.
/// https://eips.ethereum.org/EIPS/eip-1474#error-codes
pub const EthereumErrorCodes = enum(isize) {
    ContractErrorCode = 3,
    TooManyRequests = 429,
    UserRejectedRequest = 4001,
    Unauthorized = 4100,
    UnsupportedMethod = 4200,
    Disconnected = 4900,
    ChainDisconnected = 4901,
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
/// RPC errors in zig format
pub const EthereumZigErrors = error{
    EvmFailedToExecute,
    TooManyRequests,
    InvalidInput,
    ResourceNotFound,
    ResourceUnavailable,
    TransactionRejected,
    MethodNotSupported,
    LimitExceeded,
    RpcVersionNotSupported,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    ParseError,
    UnexpectedRpcErrorCode,
    UserRejectedRequest,
    Unauthorized,
    UnsupportedMethod,
    Disconnected,
    ChainDisconnected,
};
/// Zig struct representation of a RPC error response
pub const EthereumErrorResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?usize = null,
    @"error": ErrorResponse,

    pub usingnamespace RequestParser(@This());
};
/// Know ethereum events emited by the websocket client
pub const EthereumSubscribeEvents = union(enum) {
    new_heads_event: EthereumSubscribeResponse(Block),
    pending_transactions_event: EthereumSubscribeResponse(PendingTransaction),
    pending_transactions_hashes_event: EthereumSubscribeResponse(Hash),
    log_event: EthereumSubscribeResponse(Log),
    mined_transaction_hashes_event: EthereumSubscribeResponse(PendingTransactionHashesSubscription),
    mined_transaction_event: EthereumSubscribeResponse(PendingTransactionsSubscription),

    pub usingnamespace UnionParser(@This());
};
/// Type of WS events.
pub const EthereumEvents = union(enum) {
    subscribe_event: EthereumSubscribeEvents,
    rpc_event: EthereumRpcEvents,

    pub usingnamespace UnionParser(@This());
};
/// RPC Websocket events to be used by the websocket channels
pub const EthereumRpcEvents = union(enum) {
    null_event: EthereumRpcResponse(?ErrorResponse),
    proof_event: EthereumRpcResponse(ProofResult),
    logs_event: EthereumRpcResponse(Logs),
    accounts_event: EthereumRpcResponse([]const Address),
    access_list: EthereumRpcResponse(AccessListResult),
    fee_history: EthereumRpcResponse(FeeHistory),
    receipt_event: EthereumRpcResponse(TransactionReceipt),
    transaction_event: EthereumRpcResponse(Transaction),
    block_event: EthereumRpcResponse(Block),
    hash_event: EthereumRpcResponse(Hash),
    number_event: EthereumRpcResponse(u256),
    bool_event: EthereumRpcResponse(bool),
    sync_event: EthereumRpcResponse(SyncProgress),
    hex_event: EthereumRpcResponse(Hex),
    error_event: EthereumErrorResponse,

    pub usingnamespace UnionParser(@This());
};
