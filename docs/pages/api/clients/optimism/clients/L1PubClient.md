## L1Client
Optimism client used for L1 interactions.\
Currently only supports OP and not other chains of the superchain.

## Init
Starts the RPC connection
If the contracts are null it defaults to OP contracts.

## Deinit
Frees and destroys any allocated memory

## GetGame
Retrieves a valid dispute game on an L2 that occurred after a provided L2 block number.\
Returns an error if no game was found.\
`limit` is the max amount of game to search
`block_number` to filter only games that occurred after this block.\
`strategy` is weather to provide the latest game or one at random with the scope of the games that where found given the filters.

## GetGames
Retrieves the dispute games for an L2
`limit` is the max amount of game to search
`block_number` to filter only games that occurred after this block.\
If null then it will return all games.

## GetFinalizedWithdrawals
Returns if a withdrawal has finalized or not.

## GetLatestProposedL2BlockNumber
Gets the latest proposed L2 block number from the Oracle.

## GetL2HashesForDepositTransaction
Gets the l2 transaction hashes for the deposit transaction event.\
`hash` is expected to be the transaction hash from the deposit transaction.

## GetL2Output
Calls to the L2OutputOracle contract on L1 to get the output for a given L2 block

## GetL2OutputIndex
Calls to the L2OutputOracle on L1 to get the output index.

## GetPortalVersion
Retrieves the current version of the Portal contract.\
If the major is at least 3 it means that fault proofs are enabled.

## GetProvenWithdrawals
Gets a proven withdrawal.\
Will call the portal contract to get the information. If the timestamp is 0
this will error with invalid withdrawal hash.

## GetSecondsToNextL2Output
Gets the amount of time to wait in ms until the next output is posted.\
Calls the l2OutputOracle to get this information.

## GetSecondsToFinalize
Gets the amount of time to wait until a withdrawal is finalized.\
Calls the l2OutputOracle to get this information.

## GetSecondsToFinalizeGame
Gets the amount of time to wait until a dispute game has finalized
Uses the portal to find this information. Will error if the time is 0.

## GetSecondsUntilNextGame
Gets the timings until the next dispute game is submitted based on the provided `l2BlockNumber`

## GetTransactionDepositEvents
Gets the `TransactionDeposited` event logs from a transaction hash.\
To free the memory of this slice you will also need to loop through the
returned slice and free the `opaqueData` field. Memory will be duped
on that field because we destroy the Arena from the RPC request that owns
the original piece of memory that contains the data.

## GetWithdrawMessages
Gets the decoded withdrawl event logs from a given transaction receipt hash.

## WaitForNextGame
Waits until the next dispute game to be submitted based on the provided `l2BlockNumber`
This will keep pooling until it can get the `GameResult` or it exceeds the max retries.

## WaitForNextL2Output
Waits until the next L2 output is posted.\
This will keep pooling until it can get the L2Output or it exceeds the max retries.

## WaitToFinalize
Waits until the withdrawal has finalized.

