const std = @import("std");
const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;
const ParserError = std.json.ParseError;
const ParserOptions = std.json.ParseOptions;
const Token = std.json.Token;
const UnionParser = @import("meta/meta.zig").UnionParser;

pub const BlockTag = enum { latest, earliest, pending, safe, finalized };

pub const BlockNumberRequest = struct { block_number: ?usize = null, tag: ?BlockTag = .latest, include_transaction_objects: ?bool = false };
pub const BlockHashRequest = struct { block_hash: []const u8, include_transaction_objects: ?bool = false };

pub const Withdrawal = struct {
    index: []const u8,
    validatorIndex: []const u8,
    address: []const u8,
    amount: []const u8,
};

pub const Hex = []const u8;

pub const BlockBeforeMerge = struct {
    hash: ?[]const u8,
    parentHash: []const u8,
    sha3Uncles: []const u8,
    miner: []const u8,
    stateRoot: []const u8,
    transactionsRoot: []const u8,
    receiptsRoot: []const u8,
    number: ?Hex,
    gasUsed: []const u8,
    gasLimit: []const u8,
    extraData: []const u8,
    logsBloom: ?[]const u8,
    timestamp: []const u8,
    difficulty: []const u8,
    totalDifficulty: ?[]const u8,
    sealFields: []const []const u8,
    uncles: []const []const u8,
    transactions: []const []const u8,
    size: []const u8,
    mixHash: []const u8,
    nonce: ?[]const u8,
    baseFeePerGas: ?[]const u8,
};

pub const BlockAfterMerge = struct {
    hash: ?[]const u8,
    parentHash: []const u8,
    sha3Uncles: []const u8,
    miner: []const u8,
    stateRoot: []const u8,
    transactionsRoot: []const u8,
    receiptsRoot: []const u8,
    number: ?Hex,
    gasUsed: []const u8,
    gasLimit: []const u8,
    extraData: []const u8,
    logsBloom: ?[]const u8,
    timestamp: []const u8,
    difficulty: []const u8,
    totalDifficulty: ?[]const u8,
    sealFields: []const []const u8,
    uncles: []const []const u8,
    transactions: []const []const u8,
    size: []const u8,
    mixHash: []const u8,
    nonce: ?[]const u8,
    baseFeePerGas: ?[]const u8,
    withdrawalsRoot: []const u8,
    withdrawals: []const Withdrawal,
};

pub const Block = union(enum) {
    blockMerge: BlockAfterMerge,
    block: BlockBeforeMerge,

    pub usingnamespace UnionParser(@This());
};
