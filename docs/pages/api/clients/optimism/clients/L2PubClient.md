## L2Client
Optimism client used for L2 interactions.\
Currently only supports OP and not other chains of the superchain.

## Init
Starts the RPC connection
If the contracts are null it defaults to OP contracts.

## Deinit
Frees and destroys any allocated memory

## EstimateL1Gas
Returns the L1 gas used to execute L2 transactions

## EstimateL1GasFee
Returns the L1 fee used to execute L2 transactions

## EstimateTotalFees
Estimates the L1 + L2 fees to execute a transaction on L2

## EstimateTotalGas
Estimates the L1 + L2 gas to execute a transaction on L2

## GetBaseL1Fee
Returns the base fee on L1

## GetWithdrawMessages
Gets the decoded withdrawl event logs from a given transaction receipt hash.

