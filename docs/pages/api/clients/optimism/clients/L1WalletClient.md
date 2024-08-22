## WalletL1Client
Optimism wallet client used for L1 interactions.\
Currently only supports OP and not other chains of the superchain.\
This implementation is not as robust as the `Wallet` implementation.

## Init
Starts the wallet client. Init options depend on the client type.\
This has all the expected L1 actions. If you are looking for L2 actions
consider using `L2WalletClient`
If the contracts are null it defaults to OP contracts.\
Caller must deinit after use.

## Deinit
Frees and destroys any allocated memory

## DepositTransaction
Invokes the contract method to `depositTransaction`. This will send
a transaction to the network.

## EstimateDepositTransaction
Estimate the gas cost for the deposit transaction.\
Uses the portalAddress. The data is expected to be hex abi encoded data.

## EstimateFinalizeWithdrawal
Estimates the gas cost for calling `finalizeWithdrawal`

## EstimateProveWithdrawal
Estimates the gas cost for calling `proveWithdrawal`

## FinalizeWithdrawal
Invokes the contract method to `finalizeWithdrawalTransaction`. This will send
a transaction to the network.

## PrepareWithdrawalProofTransaction
Prepares a proof withdrawal transaction.

## ProveWithdrawal
Invokes the contract method to `proveWithdrawalTransaction`. This will send
a transaction to the network.

## PrepareDepositTransaction
Prepares the deposit transaction. Will error if its a creation transaction
and a `to` address was given. It will also fail if the mint and value do not match.

## SendTransaction
Sends a transaction envelope to the network. This serializes, hashes and signed before
sending the transaction.

