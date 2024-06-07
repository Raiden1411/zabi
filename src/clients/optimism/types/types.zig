const ethereum_types = @import("../../../types/ethereum.zig");

const Address = ethereum_types.Address;
const Gwei = ethereum_types.Gwei;
const Hash = ethereum_types.Hash;
const Hex = ethereum_types.Hex;
const Wei = ethereum_types.Wei;

pub const L2Output = struct {
    outputIndex: u256,
    outputRoot: Hash,
    timestamp: u128,
    l2BlockNumber: u128,
};

pub const Domain = enum(u8) {
    user_deposit = 0,
    l1_info_deposit = 1,
};

pub const GetDepositArgs = struct {
    from: Address,
    to: ?Address,
    /// This expects that the data has already been hex decoded
    opaque_data: Hex,
    domain: Domain,
    log_index: u256,
    l1_blockhash: Hash,
    source_hash: ?Hash = null,
};
