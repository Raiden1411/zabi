const types = @import("../types/ethereum.zig");
const transaction = @import("../types/transaction.zig");

const Address = types.Address;
const EthCall = transaction.EthCall;
const Hash = types.Hash;

pub const Contract = struct {
    /// The bytecode associated with this contract.
    bytecode: []u8,
    /// Address that called this contract.
    caller: Address,
    /// Keccak hash of the bytecode.
    code_hash: ?Hash = null,
    /// Gas used by this contract.
    gas: u64,
    /// The calldata input to use in this contract.
    input: []u8,
    /// The address of this contract.
    target_address: Address,
    /// Value in wei associated with this contract.
    value: u256,

    pub fn newContract(data: []u8, bytecode: []u8, hash: ?Hash, call: EthCall) Contract {
        return .{
            .input = data,
            .bytecode = bytecode,
            .code_hash = hash,
            .gas = call.london.gas orelse 0,
            .value = call.london.value orelse 0,
            .caller = call.london.from.?,
            .target_address = call.london.to.?,
        };
    }
};
