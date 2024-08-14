# Meta programming

## Definition

Zabi supports some meta programming function that could help you when working with on some more specific types

## `AbiParameterToPrimativeType`

Converts a `AbiParameter` into the native zig type.

## `AbiParametersToPrimativeType`

Converts a `[]const AbiParameter` into a tuple of native zig type.

## `AbiEventParameterDataToPrimativeType`

Converts a `AbiEventParameter` into the native zig type.

## `AbiEventParametersDataToPrimativeType`

Converts a `[]const AbiEventParameter` into a tuple of native zig type.

## `Extract`

Similar to Typescript's extract type helper.

## `MergeStructs`

Merges the fields of two structs into a single one. 

## `MergeTupleStructs`

Merges the fields of two tuples into a single one. 

## `StructToTupleType`

Convert a non tuple struct into a tuple struct.

## `Omit`

Similar to Typescript's omit type helper.

## `jsonParse`
Custom jsonParse that is mostly used to enable the ability to parse hex string values into native `int` types, since parsing hex values is not part of the JSON RFC we need to rely on the hability of zig to create a custom jsonParse method for structs.

## `jsonParseFromValue`
Custom jsonParseFromValue that is mostly used to enable the ability to parse hex string values into native `int` types, since parsing hex values is not part of the JSON RFC we need to rely on the hability of zig to create a custom jsonParseFromValue method for structs.

## `jsonStringify`
Custom jsonStringify that is mostly used to enable the ability to parse int values as hex and to parse address with checksum and to treat array and slices of `u8` as hex encoded strings.
This doesn't apply if the slice is `const`.
Parsing hex values or dealing with strings like this is not part of the JSON RFC we need to rely on the hability of zig to create a custom jsonStringify method for structs.
