const std = @import("std");
const block = @import("block.zig");
const meta = @import("../meta/root.zig");
const types = @import("ethereum.zig");

// Types
const Allocator = std.mem.Allocator;
const Address = types.Address;
const BalanceBlockTag = block.BalanceBlockTag;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;
const Wei = types.Wei;

/// Zig struct representation of the log RPC response.
pub const Log = struct {
    blockHash: ?Hash,
    address: Address,
    logIndex: ?usize,
    data: Hex,
    removed: bool,
    topics: []const ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?usize,
    transactionHash: ?Hash,
    transactionLogIndex: ?usize = null,
    blockTimestamp: ?u64 = null,

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
/// Slice of the struct log
pub const Logs = []const Log;
/// Its default all null so that when it gets stringified
/// Logs request struct used by the RPC request methods.
/// we can use `ignore_null_fields` to omit these fields
pub const LogRequest = struct {
    fromBlock: ?u64 = null,
    toBlock: ?u64 = null,
    address: ?Address = null,
    topics: ?[]const ?Hex = null,
    blockHash: ?Hash = null,

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
/// Same as `LogRequest` but `fromBlock` and
/// `toBlock` are tags.
pub const LogTagRequest = struct {
    fromBlock: ?BalanceBlockTag = null,
    toBlock: ?BalanceBlockTag = null,
    address: ?Address = null,
    topics: ?[]const ?Hex = null,
    blockHash: ?Hash = null,

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
/// Options for `watchLogs` websocket request.
pub const WatchLogsRequest = struct {
    address: Address,
    topics: ?[]const ?Hex = null,

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
