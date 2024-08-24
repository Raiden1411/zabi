## OpMainNetContracts

L1 and L2 optimism contracts

### Properties

```zig
/// L2 specific.
gasPriceOracle: Address = utils.addressToBytes("0x420000000000000000000000000000000000000F") catch unreachable
/// L2 specific.
l1Block: Address = utils.addressToBytes("0x4200000000000000000000000000000000000015") catch unreachable
/// L2 specific.
l2CrossDomainMessenger: Address = utils.addressToBytes("0x4200000000000000000000000000000000000007") catch unreachable
/// L2 specific.
l2Erc721Bridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000014") catch unreachable
/// L2 specific.
l2StandartBridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000010") catch unreachable
/// L2 specific.
l2ToL1MessagePasser: Address = utils.addressToBytes("0x4200000000000000000000000000000000000016") catch unreachable
/// L1 specific. L2OutputOracleProxy contract.
l2OutputOracle: Address = utils.addressToBytes("0xdfe97868233d1aa22e815a266982f2cf17685a27") catch unreachable
/// L1 specific. OptimismPortalProxy contract.
portalAddress: Address = utils.addressToBytes("0xbEb5Fc579115071764c7423A4f12eDde41f106Ed") catch unreachable
/// L1 specific. DisputeGameFactoryProxy contract. Make sure that the chain has fault proofs enabled.
disputeGameFactory: Address = utils.addressToBytes("0x05F9613aDB30026FFd634f38e5C4dFd30a197Fa1") catch unreachable
```

