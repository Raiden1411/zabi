const std = @import("std");
const meta = @import("../meta/root.zig");

// Types
const Allocator = std.mem.Allocator;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;

/// Result when calling `eth_syncing` if a node hasn't finished syncing
pub const SyncStatus = struct {
    startingBlock: u64,
    currentBlock: u64,
    highestBlock: u64,
    syncedAccounts: u64,
    syncedAccountsBytes: u64,
    syncedBytecodes: u64,
    syncedBytecodesBytes: u64,
    syncedStorage: u64,
    syncedStorageBytes: u64,
    healedTrienodes: u64,
    healedTrienodeBytes: u64,
    healedBytecodes: u64,
    healedBytecodesBytes: u64,
    healingTrienodes: u64,
    healingBytecode: u64,
    txIndexFinishedBlocks: u64,
    txIndexRemainingBlocks: u64,

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
