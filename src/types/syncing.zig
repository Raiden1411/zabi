const RequestParser = @import("../meta/json.zig").RequestParser;

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

    pub usingnamespace RequestParser(@This());
};
