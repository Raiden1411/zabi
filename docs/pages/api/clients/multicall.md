## Call

## Call3

## Call3Value

## Result
The result struct when calling the multicall contract.

## MulticallTargets
Arguments for the multicall3 function call

## MulticallArguments
Type function that gets the expected arguments from the provided abi's.

## aggregate3_abi
Multicall3 aggregate3 abi representation.

## multicall_contract
The multicall3 contract address. Equal across all chains.

## Multicall
Wrapper around a rpc_client that exposes the multicall3 functions.

## Init
Creates the initial state for the contract

## Multicall3
Runs the selected multicall3 contracts.\
This enables to read from multiple contract by a single `eth_call`.\
Uses the contracts created [here](https://www.multicall3.com/)
To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)

