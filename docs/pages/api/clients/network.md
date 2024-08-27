## OpMainNetContracts

L1 and L2 optimism contracts

### Properties

```zig
struct {
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
}
```

## EnsContracts

ENS Contracts

### Properties

```zig
struct {
  ensUniversalResolver: Address = utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") catch unreachable
}
```

## Endpoint

Possible endpoint locations.\
For http/s and ws/s use `Uri` and for IPC use `path`.\
If a uri connection is set for the IPC client it will create and error and vice versa.

```zig
union(enum) {
    /// If the connections is url based use this
    uri: Uri,
    /// If the connection is IPC socket based use this.
    path: []const u8,
}
```

## NetworkConfig

The possible configuration of a network.\
The only required field is the `endpoint` so that the client's
know where they can connect to.\
All other fields have default values and adjust them as you need.

### Properties

```zig
struct {
  /// The base fee multiplier used to estimate the gas fees in a transaction
  base_fee_multiplier: f64 = 1.2
  /// The client chainId.
  chain_id: Chains = .ethereum
  /// Ens contract on configured chain.
  ens_contracts: ?EnsContracts = null
  /// The multicall3 contract address.
  multicall_contract: Address = utils.addressToBytes("0xcA11bde05977b3631167028862bE2a173976CA11") catch unreachable
  /// L1 and L2 op_stack contracts
  op_stack_contracts: ?OpMainNetContracts = null
  /// The interval to retry the request. This will get multiplied in ns_per_ms.
  pooling_interval: u64 = 2_000
  /// Retry count for failed requests.
  retries: u8 = 5
  /// Uri for the client to connect to
  endpoint: Endpoint
}
```

### GetUriSchema
Gets the uri schema. Returns null if the endpoint
is configured to be `path`.

### Signature

```zig
pub fn getUriSchema(self: NetworkConfig) ?[]const u8
```

### GetNetworkUri
Gets the uri struct if possible. Return null if the endpoint
is configured to be `path`.

### Signature

```zig
pub fn getNetworkUri(self: NetworkConfig) ?Uri
```

## ethereum_mainet

The chain configuration for ethereum mainnet.

```zig
.{
    .endpoint = .{ .uri = Uri.parse("https://cloudflare-eth.com'") catch unreachable },
    .ens_contracts = .{},
}
```

