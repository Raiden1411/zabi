const utils = @import("../../utils/utils.zig");
const types = @import("../../types/ethereum.zig");

const Address = types.Address;

/// L1 and L2 optimism contracts
pub const OpMainNetContracts = struct {
    gasPriceOracle: Address = utils.addressToBytes("0x420000000000000000000000000000000000000F") catch @compileError("Invalid address"),
    l1Block: Address = utils.addressToBytes("0x4200000000000000000000000000000000000015") catch @compileError("Invalid address"),
    l2CrossDomainMessenger: Address = utils.addressToBytes("0x4200000000000000000000000000000000000007") catch @compileError("Invalid address"),
    l2Erc721Bridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000014") catch @compileError("Invalid address"),
    l2StandartBridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000010") catch @compileError("Invalid address"),
    l2ToL1MessagePasser: Address = utils.addressToBytes("0x4200000000000000000000000000000000000016") catch @compileError("Invalid address"),
    l2OutputOracle: Address = utils.addressToBytes("0xdfe97868233d1aa22e815a266982f2cf17685a27") catch @compileError("Invalid address"),
    portalAddress: Address = utils.addressToBytes("0x49048044D57e1C92A77f79988d21Fa8fAF74E97e") catch @compileError("Invalid address"),
};
