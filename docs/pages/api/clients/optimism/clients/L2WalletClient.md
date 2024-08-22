## L2WalletClient
Optimism  wallet client used for L2 interactions.\
Currently only supports OP and not other chains of the superchain.\
This implementation is not as robust as the `Wallet` implementation.

## Init
Starts the wallet client. Init options depend on the client type.\
This has all the expected L2 actions. If you are looking for L1 actions
consider using `L1WalletClient`
If the contracts are null it defaults to OP contracts.\
Caller must deinit after use.

## Deinit
Frees and destroys any allocated memory

## EstimateInitiateWithdrawal
Estimates the gas cost for calling `initiateWithdrawal`

## InitiateWithdrawal
Invokes the contract method to `initiateWithdrawal`. This will send
a transaction to the network.

## PrepareInitiateWithdrawal
Prepares the interaction with the contract method to `initiateWithdrawal`.

## SendTransaction
Sends a transaction envelope to the network. This serializes, hashes and signed before
sending the transaction.

