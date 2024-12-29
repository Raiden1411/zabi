const meta = @import("zabi-meta");
const std = @import("std");
const transactions = @import("transaction.zig");
const types = @import("ethereum.zig");
const utils = @import("zabi-utils").utils;

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Extract = meta.utils.Extract;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const Transaction = transactions.Transaction;
const Value = std.json.Value;
const Wei = types.Wei;

/// Block tag used for RPC requests.
pub const BlockTag = enum {
    latest,
    earliest,
    pending,
    safe,
    finalized,
};
/// Specific tags used in some RPC requests
pub const BalanceBlockTag = Extract(BlockTag, "latest,pending,earliest");
/// Specific tags used in some RPC requests
pub const ProofBlockTag = Extract(BlockTag, "latest,earliest");

/// Used in the RPC method requests
pub const BlockRequest = struct {
    block_number: ?u64 = null,
    tag: ?BlockTag = .latest,
    include_transaction_objects: ?bool = false,
};
/// Used in the RPC method requests
pub const BlockHashRequest = struct {
    block_hash: Hash,
    include_transaction_objects: ?bool = false,
};
/// Used in the RPC method requests
pub const BalanceRequest = struct {
    address: Address,
    block_number: ?u64 = null,
    tag: ?BalanceBlockTag = .latest,
};
/// Used in the RPC method requests
pub const BlockNumberRequest = struct {
    block_number: ?u64 = null,
    tag: ?BalanceBlockTag = .latest,
};

/// Withdrawal field struct type.
pub const Withdrawal = struct {
    index: u64,
    validatorIndex: u64,
    address: Address,
    amount: Wei,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// The most common block that can be found before the
/// ethereum merge. Doesn't contain the `withdrawals` or
/// `withdrawalsRoot` fields.
pub const LegacyBlock = struct {
    baseFeePerGas: ?Gwei = null,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// The most common block that can be found before the
/// ethereum merge. Doesn't contain the `withdrawals` or
/// `withdrawalsRoot` fields.
pub const ArbitrumBlock = struct {
    baseFeePerGas: ?Gwei = null,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    l1BlockNumber: u64,
    sendCount: u64,
    sendRoot: Hash,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Possible transactions that can be found in the
/// block struct fields.
pub const BlockTransactions = union(enum) {
    hashes: []const Hash,
    objects: []const Transaction,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .array)
            return error.UnexpectedToken;

        if (source.array.items.len == 0)
            return @unionInit(@This(), "hashes", try allocator.alloc(Hash, 0));

        const last = source.array.getLast();

        switch (last) {
            .string => {
                const arr = try allocator.alloc(Hash, source.array.items.len);
                for (source.array.items, arr) |item, *res| {
                    if (!utils.isHash(item.string))
                        return error.InvalidCharacter;

                    var hash: Hash = undefined;
                    _ = std.fmt.hexToBytes(hash[0..], item.string[2..]) catch return error.InvalidCharacter;
                    res.* = hash;
                }

                return @unionInit(@This(), "hashes", arr);
            },
            .object => return @unionInit(@This(), "objects", try std.json.parseFromValueLeaky([]const Transaction, allocator, source, options)),
            else => return error.UnexpectedToken,
        }
    }

    pub fn jsonStringify(
        self: @This(),
        stream: anytype,
    ) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try meta.json.innerStringify(value, stream),
        }
    }
};
/// Almost similar to `LegacyBlock` but with
/// the `withdrawalsRoot` and `withdrawals` fields.
pub const BeaconBlock = struct {
    baseFeePerGas: ?Gwei,
    difficulty: u256,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: u64,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    withdrawalsRoot: Hash,
    withdrawals: []const Withdrawal,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Almost similar to `BeaconBlock` but with this support blob fields
pub const BlobBlock = struct {
    baseFeePerGas: ?Gwei,
    blobGasUsed: Gwei,
    difficulty: u256,
    excessBlobGas: Gwei,
    extraData: Hex,
    gasLimit: Gwei,
    gasUsed: Gwei,
    hash: ?Hash,
    logsBloom: ?Hex,
    miner: Address,
    mixHash: ?Hash = null,
    nonce: ?u64,
    number: ?u64,
    parentBeaconBlockRoot: ?Hash = null,
    requestsRoot: ?Hash = null,
    parentHash: Hash,
    receiptsRoot: Hash,
    sealFields: ?[]const Hex = null,
    sha3Uncles: Hash,
    size: ?u64 = null,
    stateRoot: Hash,
    timestamp: u64,
    totalDifficulty: ?u256 = null,
    transactions: ?BlockTransactions = null,
    transactionsRoot: Hash,
    uncles: ?[]const Hash = null,
    withdrawalsRoot: ?Hash = null,
    withdrawals: ?[]const Withdrawal = null,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(
        self: @This(),
        writer_stream: anytype,
    ) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};
/// Union type of the possible blocks found on the network.
pub const Block = union(enum) {
    beacon: BeaconBlock,
    legacy: LegacyBlock,
    cancun: BlobBlock,
    arbitrum: ArbitrumBlock,

    pub fn jsonParse(
        allocator: Allocator,
        source: anytype,
        options: ParseOptions,
    ) ParseError(@TypeOf(source.*))!@This() {
        const json_value = try Value.jsonParse(allocator, source, options);
        return try jsonParseFromValue(allocator, json_value, options);
    }

    pub fn jsonParseFromValue(
        allocator: Allocator,
        source: Value,
        options: ParseOptions,
    ) ParseFromValueError!@This() {
        if (source != .object)
            return error.UnexpectedToken;

        if (source.object.get("blobGasUsed") != null)
            return @unionInit(@This(), "cancun", try std.json.parseFromValueLeaky(BlobBlock, allocator, source, options));

        if (source.object.get("withdrawals") != null)
            return @unionInit(@This(), "beacon", try std.json.parseFromValueLeaky(BeaconBlock, allocator, source, options));

        if (source.object.get("l1BlockNumber") != null)
            return @unionInit(@This(), "arbitrum", try std.json.parseFromValueLeaky(ArbitrumBlock, allocator, source, options));

        return @unionInit(@This(), "legacy", try std.json.parseFromValueLeaky(LegacyBlock, allocator, source, options));
    }

    pub fn jsonStringify(
        self: @This(),
        stream: anytype,
    ) @TypeOf(stream.*).Error!void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};
