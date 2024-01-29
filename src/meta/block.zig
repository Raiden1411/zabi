const meta = @import("meta.zig");
const std = @import("std");
const types = @import("ethereum.zig");
const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;
const ParserError = std.json.ParseError;
const ParserOptions = std.json.ParseOptions;
const Token = std.json.Token;

pub const BlockTag = enum { latest, earliest, pending, safe, finalized };
pub const BalanceBlockTag = meta.Extract(BlockTag, "latest,pending,earliest");

pub const BlockRequest = struct { block_number: ?u64 = null, tag: ?BlockTag = .latest, include_transaction_objects: ?bool = false };
pub const BlockHashRequest = struct { block_hash: types.Hex, include_transaction_objects: ?bool = false };
pub const BalanceRequest = struct { address: types.Hex, block_number: ?u64 = null, tag: ?BalanceBlockTag = .latest };
pub const BlockNumberRequest = struct { block_number: ?u64 = null, tag: ?BalanceBlockTag = .latest };

pub const Withdrawal = struct {
    index: u64,
    validatorIndex: u64,
    address: types.Hex,
    amount: types.Wei,

    pub usingnamespace meta.RequestParser(@This());
};

pub const BlockBeforeMerge = struct {
    hash: ?types.Hex,
    parentHash: types.Hex,
    sha3Uncles: types.Hex,
    miner: types.Hex,
    stateRoot: types.Hex,
    transactionsRoot: types.Hex,
    receiptsRoot: types.Hex,
    number: ?types.Gwei,
    gasUsed: types.Gwei,
    gasLimit: types.Gwei,
    extraData: types.Hex,
    logsBloom: ?types.Hex,
    timestamp: u64,
    difficulty: u256,
    totalDifficulty: ?types.Wei,
    sealFields: []const types.Hex,
    uncles: []const types.Hex,
    transactions: []const types.Hex,
    size: u64,
    mixHash: types.Hex,
    nonce: ?types.Gwei,
    baseFeePerGas: ?types.Gwei,

    pub usingnamespace meta.RequestParser(@This());
};

pub const BlockAfterMerge = struct {
    hash: ?types.Hex,
    parentHash: types.Hex,
    sha3Uncles: types.Hex,
    miner: types.Hex,
    stateRoot: types.Hex,
    transactionsRoot: types.Hex,
    receiptsRoot: types.Hex,
    number: ?types.Gwei,
    gasUsed: types.Gwei,
    gasLimit: types.Gwei,
    extraData: types.Hex,
    logsBloom: ?types.Hex,
    timestamp: u64,
    difficulty: u256,
    totalDifficulty: ?types.Wei,
    sealFields: []const types.Hex,
    uncles: []const types.Hex,
    transactions: []const types.Hex,
    size: u64,
    mixHash: types.Hex,
    nonce: ?types.Gwei,
    baseFeePerGas: ?types.Gwei,
    withdrawalsRoot: types.Hex,
    withdrawals: []const Withdrawal,

    pub usingnamespace meta.RequestParser(@This());
};

pub const Block = union(enum) {
    block: BlockBeforeMerge,
    blockMerge: BlockAfterMerge,

    pub usingnamespace meta.UnionParser(@This());
};
