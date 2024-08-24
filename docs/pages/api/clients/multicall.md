## Call

### Properties

```zig
struct {
  /// The target address.
  target: Address
  /// The calldata from the function that you want to run.
  callData: Hex
}
```

## Call3

### Properties

```zig
struct {
  /// The target address.
  target: Address
  /// Tells the contract weather to allow the call to fail or not.
  allowFailure: bool
  /// The calldata used to call the function you want to run.
  callData: Hex
}
```

## Call3Value

### Properties

```zig
struct {
  /// The target address.
  target: Address
  /// Tells the contract weather to allow the call to fail or not.
  allowFailure: bool
  /// The value sent in the call.
  value: u256
  /// The calldata from the function that you want to run.
  callData: Hex
}
```

## Result

The result struct when calling the multicall contract.

### Properties

```zig
struct {
  /// Weather the call was successfull or not.
  success: bool
  /// The return data from the function call.
  returnData: Hex
}
```

## MulticallTargets

Arguments for the multicall3 function call

### Properties

```zig
struct {
  function: Function
  target_address: Address
}
```

## MulticallArguments
Type function that gets the expected arguments from the provided abi's.

### Signature

```zig
pub fn MulticallArguments(comptime targets: []const MulticallTargets) type
```

## aggregate3_abi

Multicall3 aggregate3 abi representation.

## multicall_contract

The multicall3 contract address. Equal across all chains.

## Multicall
Wrapper around a rpc_client that exposes the multicall3 functions.

### Signature

```zig
pub fn Multicall(comptime client: Clients) type
```

## Init
Creates the initial state for the contract

### Signature

```zig
pub fn init(rpc_client: *Client) !Self
```

## Multicall3
Runs the selected multicall3 contracts.\
This enables to read from multiple contract by a single `eth_call`.\
Uses the contracts created [here](https://www.multicall3.com/)
To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)

### Signature

```zig
pub fn multicall3(
            self: *Self,
            comptime targets: []const MulticallTargets,
            function_arguments: MulticallArguments(targets),
            allow_failure: bool,
        ) !AbiDecoded([]const Result)
```

