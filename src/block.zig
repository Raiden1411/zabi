const meta = @import("meta/meta.zig");
const std = @import("std");
const types = @import("meta/types.zig");
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
    index: usize,
    validatorIndex: usize,
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
    number: ?types.Hex,
    gasUsed: types.Gwei,
    gasLimit: types.Gwei,
    extraData: types.Hex,
    logsBloom: ?types.Hex,
    timestamp: u64,
    difficulty: usize,
    totalDifficulty: ?usize,
    sealFields: []const types.Hex,
    uncles: []const types.Hex,
    transactions: []const types.Hex,
    size: usize,
    mixHash: types.Hex,
    nonce: ?usize,
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
    number: ?types.Hex,
    gasUsed: types.Gwei,
    gasLimit: types.Gwei,
    extraData: types.Hex,
    logsBloom: ?types.Hex,
    timestamp: u64,
    difficulty: usize,
    totalDifficulty: ?usize,
    sealFields: []const types.Hex,
    uncles: []const types.Hex,
    transactions: []const types.Hex,
    size: usize,
    mixHash: types.Hex,
    nonce: ?usize,
    baseFeePerGas: ?types.Gwei,
    withdrawalsRoot: types.Hex,
    withdrawals: []const Withdrawal,

    pub usingnamespace meta.RequestParser(@This());
};

pub const Block = union(enum) {
    blockMerge: BlockAfterMerge,
    block: BlockBeforeMerge,

    pub usingnamespace meta.UnionParser(@This());
};
