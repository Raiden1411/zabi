const utils = @import("../../utils/utils.zig");
const types = @import("../../types/ethereum.zig");

const Address = types.Address;

/// ENS Contracts
pub const EnsContracts = struct {
    ensUniversalResolver: Address = utils.addressToBytes("0xce01f8eee7E479C928F8919abD53E553a36CeF67") catch unreachable,
};
