const json_meta = @import("../meta/json.zig");
const types = @import("ethereum.zig");

// Types
const Address = types.Address;
const Hash = types.Hash;
const Hex = types.Hex;
const RequestParser = json_meta.RequestParser;
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

    pub usingnamespace RequestParser(@This());
};

pub const StorageProof = struct {
    key: Hash,
    value: Wei,
    /// Array of RLP-serialized MerkleTree-Nodes
    proof: []const Hex,

    pub usingnamespace RequestParser(@This());
};
