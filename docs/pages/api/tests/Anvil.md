## Forking
Values needed for the `anvil_reset` request.

## JsonParse

## JsonParseFromValue

## JsonStringify

## Reset
Struct representation of a `anvil_reset` request.

## JsonParse

## JsonParseFromValue

## JsonStringify

## AnvilRequest
Similar to Ethereum RPC Request but only for `AnvilMethods`.

## JsonParse

## JsonParseFromValue

## JsonStringify

## AnvilMethods
Set of methods implemented by this client for use with anvil.

## AnvilStartOptions
All startup options for starting an anvil proccess.\
All `null` or `false` will not be emitted if you use `parseToArgumentsSlice`

## ParseToArgumentsSlice
Converts `self` into a list of slices that will be used by the `anvil process.`
If `self` is set with default value only the `anvil` command will be set in the list.

## InitOptions
Set of inital options to start the http client.

## InitClient
Inits the client but doesn't start a seperate process.\
Use this if you already have an `anvil` instance running

## InitProcess
Start the `anvil` as a child process. The arguments list will be created based on
`AnvilStartOptions`. This will need to allocate memory since it will create the list.\
If `options` are set to their default value it will only start with `anvil` and no arguments.

## Deinit
Cleans up the http client

## SetBalance
Sets the balance of a anvil account

## SetCode
Changes the contract code of a address.

## SetRpcUrl
Changes the rpc of the anvil connection

## SetCoinbase
Changes the coinbase address

## SetLoggingEnable
Enable anvil verbose logging for anvil.

## SetMinGasPrice
Changes the min gasprice from the anvil fork

## SetNextBlockBaseFeePerGas
Changes the block base fee from the anvil fork

## SetChainId
Changes the networks chainId

## SetNonce
Changes the nonce of a account

## DropTransaction
Drops a pending transaction from the mempool

## Mine
Mine a pending transaction

## Reset
Reset the fork

## ImpersonateAccount
Impersonate a EOA or contract. Call `stopImpersonatingAccount` after.

## StopImpersonatingAccount
Stops impersonating a EOA or contract.

