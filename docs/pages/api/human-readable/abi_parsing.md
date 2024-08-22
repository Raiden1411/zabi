## AbiParsed

## Deinit

## ParseHumanReadable
Main function to use when wanting to use the human readable parser
This function will allocate and use and ArenaAllocator for its allocations
Caller owns the memory and must free the memory.\
Use the handy `deinit()` method provided by the return type
The return value will depend on the abi type selected.\
The function will return an error if the provided type doesn't match the
tokens from the provided signature

