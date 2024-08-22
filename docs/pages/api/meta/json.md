## JsonParse
Custom jsonParse that is mostly used to enable
the ability to parse hex string values into native `int` types,
since parsing hex values is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonParse method for structs

## JsonParseFromValue
Custom jsonParseFromValue that is mostly used to enable
the ability to parse hex string values into native `int` types,
since parsing hex values is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonParseFromValue method for structs

## JsonStringify
Custom jsonStringify that is mostly used to enable
the ability to parse int values as hex and to parse address with checksum
and to treat array and slices of `u8` as hex encoded strings. This doesn't
apply if the slice is `const`.\
Parsing hex values or dealing with strings like this is not part of the JSON RFC we need to rely on
the hability of zig to create a custom jsonStringify method for structs

## InnerParseValueRequest
Inner parser that enables the behaviour described above.\
We don't use the `innerParse` from slice because the slice is get parsed
as a json dynamic `Value`.

## InnerStringify
Inner stringifier that enables the behaviour described above.

