const block = @import("block.zig");
const meta = @import("meta.zig");
const types = @import("ethereum.zig");

pub const Log = struct {
    address: types.Hex,
    topics: []const types.Hex,
    blockHash: ?types.Hex,
    blockNumber: ?u64,
    data: types.Hex,
    logIndex: ?usize,
    transactionHash: ?types.Hex,
    transactionIndex: ?usize,
    removed: bool,

    pub usingnamespace meta.RequestParser(@This());
};

pub const Logs = []const Log;

pub const LogRequest = struct {
    fromBlock: ?types.Hex = null,
    toBlock: ?types.Hex = null,
    address: ?types.Hex = null,
    topics: ?[]const types.Hex = null,
    blockHash: ?types.Hex = null,
};

pub const LogRequestParams = struct {
    fromBlock: ?u64 = null,
    toBlock: ?u64 = null,
    tag: ?block.BalanceBlockTag = null,
    address: ?types.Hex = null,
    topics: ?[]const types.Hex = null,
    blockHash: ?types.Hex = null,
};

pub const LogFilterRequestParams = struct {
    fromBlock: ?u64 = null,
    toBlock: ?u64 = null,
    tag: ?block.BalanceBlockTag = null,
    address: ?types.Hex = null,
    topics: ?[]const types.Hex = null,
};
