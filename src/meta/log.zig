const block = @import("block.zig");
const meta = @import("meta.zig");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const BalanceBlockTag = block.BalanceBlockTag;
const Extract = meta.Extract;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const RequestParser = meta.RequestParser;
const UnionParser = meta.UnionParser;
const Wei = types.Wei;

/// Zig struct representation of the log RPC response.
pub const Log = struct {
    address: Address,
    topics: []const Hex,
    blockHash: ?Hash,
    blockNumber: ?u64,
    data: Hex,
    logIndex: ?usize,
    transactionHash: ?Hash,
    transactionIndex: ?usize,
    removed: bool,

    pub usingnamespace RequestParser(@This());
};
/// Slice of the struct log
pub const Logs = []const Log;
/// Its default all null so that when it gets stringified
/// Logs request struct used by the RPC request methods.
/// we can use `ignore_null_fields` to omit these fields
pub const LogRequest = struct {
    fromBlock: ?u64 = null,
    toBlock: ?u64 = null,
    address: ?Address = null,
    topics: ?[]const Hex = null,
    blockHash: ?Hash = null,

    pub usingnamespace RequestParser(@This());
};
pub const LogTagRequest = struct {
    fromBlock: ?BalanceBlockTag = null,
    toBlock: ?BalanceBlockTag = null,
    address: ?Address = null,
    topics: ?[]const Hex = null,
    blockHash: ?Hash = null,

    pub usingnamespace RequestParser(@This());
};
