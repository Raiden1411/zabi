# Meta programming

## Definition

Zabi supports some meta programming function that could help you when working with on some more specific types

## `AbiParameterToPrimativeType`

Converts a `AbiParameter` into the native zig type.

## `AbiParametersToPrimativeType`

Converts a `[]const AbiParameter` into a tuple of native zig type.

## `UnionParser`

Used to help json parse union types where the field is not a json object.
This was copied from the ZLS code base.

## `RequestParser`

Custom json parser. This is usefull for converting hex strings to native int values since the json RFC doesn't support parsing those string.
So with the ability that zig has of letting you create custom `jsonParse` methods for `Structs`, `Union` and `Enums` this was created. It's mostly used internally when the client makes requests to the RPC endpoint.

## `Extract`

Similar to Typescript's extract type helper.
