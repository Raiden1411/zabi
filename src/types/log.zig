const block = @import("block.zig");
const meta = @import("../meta/root.zig");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const BalanceBlockTag = block.BalanceBlockTag;
const Extract = meta.Extract;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const RequestParser = meta.json.RequestParser;
const UnionParser = meta.json.UnionParser;
const Wei = types.Wei;

/// Zig struct representation of the log RPC response.
pub const Log = struct {
    blockHash: ?Hash,
    address: Address,
    logIndex: ?usize,
    data: Hex,
    removed: bool,
    topics: []const Hex,
    blockNumber: ?u64,
    transactionLogIndex: ?usize = null,
    transactionIndex: ?usize,
    transactionHash: ?Hash,

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
