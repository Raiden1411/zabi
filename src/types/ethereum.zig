const block = @import("block.zig");
const log = @import("log.zig");
const meta = @import("zabi-meta");
const proof = @import("proof.zig");
const std = @import("std");
const sync = @import("syncing.zig");
const transaction = @import("transaction.zig");
const txpool = @import("txpool.zig");

const AccessListResult = transaction.AccessListResult;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Block = block.Block;
const FeeHistory = transaction.FeeHistory;
const Log = log.Log;
const Logs = log.Logs;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const PoolTransactionByNonce = txpool.PoolTransactionByNonce;
const ProofResult = proof.ProofResult;
const SyncProgress = sync.SyncStatus;
const Transaction = transaction.Transaction;
const TransactionReceipt = transaction.TransactionReceipt;
const TxPoolContent = txpool.TxPoolContent;
const TxPoolInspect = txpool.TxPoolInspect;
const TxPoolStatus = txpool.TxPoolStatus;
const Value = std.json.Value;

pub const Hex = []u8;
pub const Gwei = u64;
pub const Wei = u256;
pub const Hash = [32]u8;
pub const Address = [20]u8;

pub const Subscriptions = enum {
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
    txpool_content,
    txpool_contentFrom,
    txpool_inspect,
    txpool_status,
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

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            return meta.json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            return meta.json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
            return meta.json.jsonStringify(@This(), self, writer_stream);
        }
    };
}
pub fn EthereumResponse(comptime T: type) type {
    return union(enum) {
        success: EthereumRpcResponse(T),
        @"error": EthereumErrorResponse,

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            const json_value = try Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            if (source != .object)
                return error.UnexpectedToken;

            if (source.object.get("error") != null) {
                return @unionInit(@This(), "error", try std.json.parseFromValueLeaky(EthereumErrorResponse, allocator, source, options));
            }

            if (source.object.get("result") != null) {
                return @unionInit(@This(), "success", try std.json.parseFromValueLeaky(EthereumRpcResponse(T), allocator, source, options));
            }

            return error.MissingField;
        }

        pub fn jsonStringify(self: @This(), stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}
/// Zig struct representation of a RPC Response
pub fn EthereumRpcResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: ?usize = null,
        result: T,

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            return meta.json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            return meta.json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
            return meta.json.jsonStringify(@This(), self, writer_stream);
        }
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

            pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
                return meta.json.jsonParse(@This(), allocator, source, options);
            }

            pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
                return meta.json.jsonParseFromValue(@This(), allocator, source, options);
            }

            pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
                return meta.json.jsonStringify(@This(), self, writer_stream);
            }
        },

        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
            return meta.json.jsonParse(@This(), allocator, source, options);
        }

        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
            return meta.json.jsonParseFromValue(@This(), allocator, source, options);
        }

        pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
            return meta.json.jsonStringify(@This(), self, writer_stream);
        }
    };
}
/// Zig struct representation of a RPC error message
pub const ErrorResponse = struct {
    code: EthereumErrorCodes,
    message: []const u8,
    data: ?[]const u8 = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Zig struct representation of a contract error response
pub const ContractErrorResponse = struct {
    code: EthereumErrorCodes,
    message: []const u8,
    data: []const u8,
};
/// Ethereum RPC error codes.
/// https://eips.ethereum.org/EIPS/eip-1474#error-codes
pub const EthereumErrorCodes = enum(i64) {
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

    pub fn jsonStringify(code: EthereumErrorCodes, stream: anytype) @TypeOf(stream.*).Error!void {
        try stream.write(@intFromEnum(code));
    }
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

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
