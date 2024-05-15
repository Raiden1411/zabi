const types = @import("../types/ethereum.zig");

const Address = types.Address;
const Hash = types.Hash;

pub const Contract = struct {
    /// The address of this contract.
    address: Address,
    /// Address that called this contract.
    caller: Address,
    /// The bytecode associated with this contract.
    code: []u8,
    /// Keccak hash of the bytecode.
    code_hash: ?Hash = null,
    /// The address that initialized this contract.
    creator: Address,
    /// Gas used by this contract.
    gas: u64,
    /// The calldata input to use in this contract.
    input: ?[]u8,
    /// If the contract is being used on a deployment transaction.
    is_deployment: bool,
    /// Value in wei associated with this contract.
    value: u256,
};
