## ENSClient
A public client that interacts with the ENS contracts.\
Currently ENSAvatar is not supported but will be in future versions.

## Init
Starts the RPC connection
If the contracts are null it defaults to mainnet contracts.

## Deinit
Frees and destroys any allocated memory

## GetEnsAddress
Gets the ENS address associated with the ENS name.\
Caller owns the memory if the request is successfull.\
Calls the resolver address and decodes with address resolver.\
The names are not normalized so make sure that the names are normalized before hand.

## GetEnsName
Gets the ENS name associated with the address.\
Caller owns the memory if the request is successfull.\
Calls the reverse resolver and decodes with the same.\
This will fail if its not a valid checksumed address.

## GetEnsResolver
Gets the ENS resolver associated with the name.\
Caller owns the memory if the request is successfull.\
Calls the find resolver and decodes with the same one.\
The names are not normalized so make sure that the names are normalized before hand.

## GetEnsText
Gets a text record for a specific ENS name.\
Caller owns the memory if the request is successfull.\
Calls the resolver and decodes with the text resolver.\
The names are not normalized so make sure that the names are normalized before hand.

