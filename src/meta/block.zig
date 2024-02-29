const meta = @import("meta.zig");
const std = @import("std");
const transactions = @import("transaction.zig");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Extract = meta.Extract;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const ParserError = std.json.ParseError;
const ParserOptions = std.json.ParseOptions;
const RequestParser = meta.RequestParser;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const Transaction = transactions.Transaction;
const UnionParser = meta.UnionParser;
const Wei = types.Wei;

/// Block tag used for RPC requests.
pub const BlockTag = enum { latest, earliest, pending, safe, finalized };
/// Specific tags used in some RPC requests
pub const BalanceBlockTag = Extract(BlockTag, "latest,pending,earliest");
/// Used in the RPC method requests
pub const BlockRequest = struct { block_number: ?u64 = null, tag: ?BlockTag = .latest, include_transaction_objects: ?bool = false };
/// Used in the RPC method requests
pub const BlockHashRequest = struct { block_hash: Hex, include_transaction_objects: ?bool = false };
/// Used in the RPC method requests
pub const BalanceRequest = struct { address: Hex, block_number: ?u64 = null, tag: ?BalanceBlockTag = .latest };
/// Used in the RPC method requests
pub const BlockNumberRequest = struct { block_number: ?u64 = null, tag: ?BalanceBlockTag = .latest };

/// Withdrawal field struct type.
pub const Withdrawal = struct {
    index: u64,
    validatorIndex: u64,
    address: Address,
    amount: Wei,

    pub usingnamespace RequestParser(@This());
};
/// The most common block that can be found before the
/// ethereum merge. Doesn't contain the `withdrawals` or
/// `withdrawalsRoot` fields.
pub const LegacyBlock = struct {
    hash: ?Hash,
    parentHash: Hash,
    sha3Uncles: Hash,
    miner: Address,
    stateRoot: Hash,
    transactionsRoot: Hash,
    receiptsRoot: Hash,
    number: ?u64,
    gasUsed: Gwei,
    gasLimit: Gwei,
    extraData: Hex,
    logsBloom: ?Hex,
    timestamp: u64,
    difficulty: u256,
    totalDifficulty: ?u256,
    sealFields: []const Hash,
    uncles: []const Hash,
    transactions: BlockTransactions,
    size: u64,
    mixHash: Hash,
    nonce: ?u64,
    baseFeePerGas: ?Gwei,

    pub usingnamespace RequestParser(@This());
};
/// Possible transactions that can be found in the
/// block struct fields.
pub const BlockTransactions = union(enum) {
    hashes: []const Hex,
    objects: []const Transaction,

    pub usingnamespace UnionParser(@This());
};
/// Almost similar to `BlockBeforeMerge` but with
/// the `withdrawalsRoot` and `withdrawals` fields.
pub const BeaconBlock = struct {
    hash: ?Hash,
    parentHash: Hash,
    sha3Uncles: Hash,
    miner: Address,
    stateRoot: Hash,
    transactionsRoot: Hash,
    receiptsRoot: Hash,
    number: ?u64,
    gasUsed: Gwei,
    gasLimit: Gwei,
    extraData: Hex,
    logsBloom: ?Hex,
    timestamp: u64,
    difficulty: u256,
    totalDifficulty: ?u256,
    sealFields: []const Hash,
    uncles: []const Hash,
    transactions: BlockTransactions,
    size: u64,
    mixHash: Hash,
    nonce: ?u64,
    baseFeePerGas: ?u64,
    withdrawalsRoot: Hash,
    withdrawals: []const Withdrawal,

    pub usingnamespace RequestParser(@This());
};
/// Union type of the possible block found on the network.
pub const Block = union(enum) {
    beacon: BeaconBlock,
    legacy: LegacyBlock,

    pub usingnamespace UnionParser(@This());
};
