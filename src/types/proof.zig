const std = @import("std");
const meta = @import("zabi-meta");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Hash = types.Hash;
const Hex = types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;
const Wei = types.Wei;

/// Eth get proof rpc request.
pub const ProofRequest = struct {
    address: Address,
    storageKeys: []const Hash,
    blockNumber: ?u64 = null,
};
/// Result of eth_getProof
pub const ProofResult = struct {
    address: Address,
    balance: Wei,
    codeHash: Hash,
    nonce: u64,
    storageHash: Hash,
    /// Array of RLP-serialized MerkleTree-Nodes
    accountProof: []const Hex,
    storageProof: []const StorageProof,

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

pub const StorageProof = struct {
    key: Hash,
    value: Wei,
    /// Array of RLP-serialized MerkleTree-Nodes
    proof: []const Hex,

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
