## Abitype

## Function
Solidity Abi function representation.\
Reference: ["function"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Deinit

## Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiFunctionComptime` if the struct is
comptime know and you want better typesafety from the compiler

## EncodeOutputs
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `outputs` proprety.\
Caller owns the memory.\
Consider using `EncodeAbiFunctionComptime` if the struct is
comptime know and you want better typesafety from the compiler

## Decode
Decode a encoded function based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiFunction` if the struct is
comptime know and you dont want to provided the return type.

## DecodeOutputs
Decode a encoded function based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `outputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiFunction` if the struct is
comptime know and you dont want to provided the return type.

## Format
Format the struct into a human readable string.

## AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

## Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

## Event
Solidity Abi function representation.\
Reference: ["event"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Deinit

## Format
Format the struct into a human readable string.

## Encode
Encode the struct signature based it's hash.\
Caller owns the memory.\
Consider using `EncodeAbiEventComptime` if the struct is
comptime know and you want better typesafety from the compiler

## EncodeLogTopics
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.

## DecodeLogTopics
Decode the encoded log topics based on the event signature and the provided type.\
Caller owns the memory.

## AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

## Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

## Error
Solidity Abi function representation.\
Reference: ["error"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Deinit

## Format
Format the struct into a human readable string.

## Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiErrorComptime` if the struct is
comptime know and you want better typesafety from the compiler

## Decode
Decode a encoded error based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiError` if the struct is
comptime know and you dont want to provided the return type.

## AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

## Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

## Constructor
Solidity Abi function representation.\
Reference: ["constructor"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Deinit

## Format
Format the struct into a human readable string.

## Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiConstructorComptime` if the struct is
comptime know and you want better typesafety from the compiler

## Decode
Decode a encoded constructor arguments based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiConstructor` if the struct is
comptime know and you dont want to provided the return type.

## Fallback
Solidity Abi function representation.\
Reference: ["fallback"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Format
Format the struct into a human readable string.

## Receive
Solidity Abi function representation.\
Reference: ["receive"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

## Format
Format the struct into a human readable string.

## AbiItem
Union representing all of the possible Abi members.

## JsonParse

## JsonParseFromValue

## Deinit

## Format

## Abi
Abi representation in ZIG.

