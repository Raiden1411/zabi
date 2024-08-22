## ParamErrors

## FixedArray

## ParamType

## FreeArrayParamType
User must call this if the union type contains a fixedArray or dynamicArray field.\
They create pointers so they must be destroyed after.

## JsonParse
Overrides the `jsonParse` from `std.json`.\
We do this because a union is treated as expecting a object string in Zig.\
But since we are expecting a string that contains the type value
we override this so we handle the parsing properly and still leverage the union type.

## JsonParseFromValue

## JsonStringify

## TypeToJsonStringify

## TypeToString

## TypeToUnion
Helper function that is used to convert solidity types into zig unions,
the function will allocate if a array or a fixed array is used.\
Consider using `freeArrayParamType` to destroy the pointers
or call the destroy method on your allocator manually

