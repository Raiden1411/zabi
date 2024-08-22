## Modules
The block explorer modules.

## Actions
The block explorer actions.

## InitOpts
The client init options

## QueryParameters
Used by the `Explorer` client to build the uri query parameters.

## BuildQuery
Build the query based on the provided `value` and it's inner state.\
Uses the `QueryWriter` to build the searchUrlParams.

## BuildDefaultQuery
Build the query parameters without any provided values.\
Uses the `QueryWriter` to build the searchUrlParams.

## Init
Creates the initial client state.\
This client only supports the free api endpoints via the api. We will not support PRO methods.\
But `zabi` has all the tools you will need to create the methods to target those endpoints.\
This only supports etherscan like block explorers.

## Deinit
Deinits the http/s server.

## GetAbi
Queries the api endpoint to find the `address` contract ABI.

## GetAddressBalance
Queries the api endpoint to find the `address` balance at the specified `tag`

## GetBlockCountDown
Queries the api endpoint to find the block reward at the specified `block_number`

## GetBlockNumberByTimestamp
Queries the api endpoint to find the block reward at the specified `block_number`

## GetBlockReward
Queries the api endpoint to find the block reward at the specified `block_number`

## GetContractCreation
Queries the api endpoint to find the creation tx address from the target contract addresses.

## GetEstimationOfConfirmation
Queries the api endpoint to find the `address` balance at the specified `tag`

## GetErc20TokenBalance
Queries the api endpoint to find the `address` erc20 token balance.

## GetErc20TokenSupply
Queries the api endpoint to find the `address` erc20 token supply.

## GetErc20TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

## GetErc721TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

## GetErc1155TokenTransferEvents
Queries the api endpoint to find the `address` and `contractaddress` erc20 token transaction events based on a block range.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

## GetEtherPrice
Queries the api endpoint to find the `address` erc20 token balance.

## GetInternalTransactionList
Queries the api endpoint to find the `address` internal transaction list based on a block range.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`.

## GetInternalTransactionListByHash
Queries the api endpoint to find the internal transactions from a transaction hash.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`.

## GetInternalTransactionListByRange
Queries the api endpoint to find the `address` balances at the specified `tag`
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

## GetLogs
Queries the api endpoint to find the logs at the target `address` based on the provided block range.

## GetMultiAddressBalance
Queries the api endpoint to find the `address` balances at the specified `tag`

## GetSourceCode
Queries the api endpoint to find the `address` contract source information if it's present.\
The api might send the result with empty field in case the source information is not present.\
This will cause the json parse to fail.

## GetTotalEtherSupply
Queries the api endpoint to find the `address` erc20 token balance.

## GetTransactionList
Queries the api endpoint to find the `address` transaction list based on a block range.\
This can fail because the response can be higher than `max_append_size`.\
If the stack trace points to the reader failing consider either changing the provided `QueryOptions`
or increasing the `max_append_size`

## GetTransactionReceiptStatus
Queries the api endpoint to find the transaction receipt status based on the provided `hash`

## GetTransactionStatus
Queries the api endpoint to find the transaction status based on the provided `hash`

## SendRequest
Writes request to endpoint and parses the response according to the provided type.\
Handles 429 errors but not the rest.\
Builds the uri from the endpoint's api url plus the query parameters from the provided `value`
and possible set `QueryOptions`. The current max buffer size is 4096.\
`value` must be a non tuple struct type.

