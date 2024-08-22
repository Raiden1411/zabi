## AbiParameter
Struct to represent solidity Abi Paramters

## Deinit

## Encode
Encode the paramters based on the values provided and `self`.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `encodeAbiParametersComptime` if the parameter is
comptime know and you want better typesafety from the compiler

## Decode
Decode the paramters based on self.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory only if the param type is a dynamic array
Consider using `decodeAbiParameters` if the parameter is
comptime know and you want better typesafety from the compiler

## Format
Format the struct into a human readable string.

## Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

## AbiEventParameter
Struct to represent solidity Abi Event Paramters

## Deinit

## Format
Format the struct into a human readable string.

## Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

