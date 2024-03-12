const ethereum_types = @import("../../../types/ethereum.zig");
const meta = @import("../../../meta/json.zig");

const Address = ethereum_types.Address;
const Gwei = ethereum_types.Gwei;
const Hash = ethereum_types.Hash;
const Hex = ethereum_types.Hex;
const RequestParser = meta.RequestParser;
const Wei = ethereum_types.Wei;

pub const L2Output = struct { outputIndex: u256, outputRoot: Hash, timestamp: u128, l2BlockNumber: u128 };
