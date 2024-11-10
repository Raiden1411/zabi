## EncodeErrors

Set of errors while perfoming abi encoding.

```zig
Allocator.Error || error{NoSpaceLeft}
```

## AbiEncodedValues

Runtime value representation for abi encoding.

### Properties

```zig
union(enum) {
  bool: bool
  uint: u256
  int: i256
  address: Address
  fixed_bytes: []u8
  string: []const u8
  bytes: []const u8
  fixed_array: []const AbiEncodedValues
  dynamic_array: []const AbiEncodedValues
  tuple: []const AbiEncodedValues
}
```

### IsDynamic
Checks if the given values is a dynamic abi value.

### Signature

```zig
pub fn isDynamic(self: @This()) bool
```

## PreEncodedStructure

The encoded values inner structure representation.

### Properties

```zig
struct {
  dynamic: bool
  encoded: []const u8
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

## EncodeAbiFunction
Encode an Solidity `Function` type with the signature and the values encoded.
The signature is calculated by hashing the formated string generated from the `Function` signature.

### Signature

```zig
pub fn encodeAbiFunction(
    comptime func: Function,
    allocator: Allocator,
    values: AbiParametersToPrimative(func.inputs),
) EncodeErrors![]u8
```

## EncodeAbiFunctionOutputs
Encode an Solidity `Function` type with the signature and the values encoded.
This is will use the `func` outputs values as the parameters.

### Signature

```zig
pub fn encodeAbiFunctionOutputs(
    comptime func: Function,
    allocator: Allocator,
    values: AbiParametersToPrimative(func.outputs),
) Allocator.Error![]u8
```

## EncodeAbiError
Encode an Solidity `Error` type with the signature and the values encoded.
The signature is calculated by hashing the formated string generated from the `Error` signature.

### Signature

```zig
pub fn encodeAbiError(
    comptime err: Error,
    allocator: Allocator,
    values: AbiParametersToPrimative(err.inputs),
) EncodeErrors![]u8
```

## EncodeAbiConstructor
Encode an Solidity `Constructor` type with the signature and the values encoded.

### Signature

```zig
pub fn encodeAbiConstructor(
    comptime constructor: Constructor,
    allocator: Allocator,
    values: AbiParametersToPrimative(constructor.inputs),
) Allocator.Error![]u8
```

## EncodeAbiParameters
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

The values types are checked at comptime based on the provided `params`.

### Signature

```zig
pub fn encodeAbiParameters(
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) Allocator.Error![]u8
```

## EncodeAbiParametersValues
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

Use this if for some reason you don't know the `Abi` at comptime.

It's recommended to use `encodeAbiParameters` whenever possible but this is provided as a fallback
you cannot use it.

### Signature

```zig
pub fn encodeAbiParametersValues(
    allocator: Allocator,
    values: []const AbiEncodedValues,
) (Allocator.Error || error{InvalidType})![]u8
```

## EncodeAbiParametersFromReflection
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

This will use zig's ability to provide compile time reflection based on the `values` provided.
The `values` must be a tuple struct. Otherwise it will trigger a compile error.

By default this provides more support for a greater range on zig types that can be used for encoding.
Bellow you will find the list of all supported types and what will they be encoded as.

  * Zig `bool` -> Will be encoded like a boolean value
  * Zig `?T` -> Only encodes if the value is not null.
  * Zig `int`, `comptime_int` -> Will be encoded based on the signedness of the integer.
  * Zig `[N]u8` -> Only support max size of 32. `[20]u8` will be encoded as address types and all other as bytes1..32.
                   This is the main limitation because abi encoding of bytes1..32 follows little endian and for address follows big endian.
  * Zig `enum` -> The tagname of the enum encoded as a string/bytes value.
  * Zig `*T` -> will encoded the child type. If the child type is an `array` it will encode as string/bytes.
  * Zig `[]const u8`, `[]u8` -> Will encode according the string/bytes specification.
  * Zig `[]const T` -> Will encode as a dynamic array
  * Zig `[N]T` -> Will encode as a dynamic value if the child type is of a dynamic type.
  * Zig `struct` -> Will encode as a dynamic value if the child type is of a dynamic type.

All other types are currently not supported.

### Signature

```zig
pub fn encodeAbiParametersFromReflection(
    allocator: Allocator,
    values: anytype,
) Allocator.Error![]u8
```

## AbiEncoder

The abi encoding structure used to encoded values with the abi encoding [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

You can initialize this structure like this:
```zig
var encoder: AbiEncoder = .empty;

try encoder.encodeAbiParameters(params, allocator, .{69, 420});
defer allocator.free(allocator);
```

### Properties

```zig
struct {
  /// Essentially a `stack` of encoded values that will need to be analysed
  /// in the `encodePointers` step to re-arrange the location in the encoded slice based on
  /// if they are dynamic or static types.
  pre_encoded: ArrayListUnmanaged(PreEncodedStructure)
  /// Stream of encoded values that should show up at the top of the encoded slice.
  heads: ArrayListUnmanaged(u8)
  /// Stream of encoded values that should show up at the end of the encoded slice.
  tails: ArrayListUnmanaged(u8)
  /// Used to calculated the initial pointer when facing `dynamic` types.
  /// Also used to know the memory size of the `heads` stream.
  heads_size: u32
  /// Only used to know the memory size of the `tails` stream.
  tails_size: u32
}
```

## Self

```zig
@This()
```

## empty

Sets the initial state of the encoder.

```zig
.{
        .pre_encoded = .empty,
        .heads = .empty,
        .tails = .empty,
        .heads_size = 0,
        .tails_size = 0,
    }
```

### EncodeAbiParametersFromReflection
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

Uses compile time reflection to determine the behaviour. Please check `encodeAbiParametersFromReflection` for more details.

### Signature

```zig
pub fn encodeAbiParametersFromReflection(
    self: *Self,
    allocator: Allocator,
    values: anytype,
) Allocator.Error![]u8
```

### EncodeAbiParametersValues
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

Uses the `AbiEncodedValues` type to determine the correct behaviour.

### Signature

```zig
pub fn encodeAbiParametersValues(
    self: *Self,
    allocator: Allocator,
    values: []const AbiEncodedValues,
) Allocator.Error![]u8
```

### EncodeAbiParameters
Encodes the `values` based on the [specification](https://docs.soliditylang.org/en/develop/abi-spec.html#use-of-dynamic-types)

The values types are checked at comptime based on the provided `params`.

### Signature

```zig
pub fn encodeAbiParameters(
    self: *Self,
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) Allocator.Error![]u8
```

### EncodePointers
Re-arranges the inner stack based on if the value that it's dealing with is either dynamic or now.
Places those values in the `heads` or `tails` streams based on that.

### Signature

```zig
pub fn encodePointers(self: *Self, allocator: Allocator) Allocator.Error![]u8
```

### PreEncodeAbiParameters
Encodes the values and places them on the `inner` stack.

### Signature

```zig
pub fn preEncodeAbiParameters(
    self: *Self,
    comptime params: []const AbiParameter,
    allocator: Allocator,
    values: AbiParametersToPrimative(params),
) Allocator.Error!void
```

### PreEncodeAbiParameter
Encodes a single value and places them on the `inner` stack.

### Signature

```zig
pub fn preEncodeAbiParameter(
    self: *Self,
    comptime param: AbiParameter,
    allocator: Allocator,
    value: AbiParameterToPrimative(param),
) Allocator.Error!void
```

### PreEncodeRuntimeValues
Pre encodes the parameter values according to the specification and places it on `pre_encoded` arraylist.

### Signature

```zig
pub fn preEncodeRuntimeValues(
    self: *Self,
    allocator: Allocator,
    values: []const AbiEncodedValues,
) (error{InvalidType} || Allocator.Error)!void
```

### PreEncodeRuntimeValue
Pre encodes the parameter value according to the specification and places it on `pre_encoded` arraylist.

This methods and some runtime checks to see if the parameter are valid like `preEncodeAbiParameter` that instead uses
comptime to get the exact expected types.

### Signature

```zig
pub fn preEncodeRuntimeValue(
    self: *Self,
    allocator: Allocator,
    value: AbiEncodedValues,
) (error{InvalidType} || Allocator.Error)!void
```

### PreEncodeValuesFromReflection
This will use zig's ability to provide compile time reflection based on the `values` provided.
The `values` must be a tuple struct. Otherwise it will trigger a compile error.

### Signature

```zig
pub fn preEncodeValuesFromReflection(self: *Self, allocator: Allocator, values: anytype) Allocator.Error!void
```

### PreEncodeReflection
This will use zig's ability to provide compile time reflection based on the `value` provided.

### Signature

```zig
pub fn preEncodeReflection(self: *Self, allocator: Allocator, value: anytype) Allocator.Error!void
```

## Self

```zig
@This()
```

## empty

Sets the initial state of the encoder.

```zig
.{
        .pre_encoded = .empty,
        .heads = .empty,
        .tails = .empty,
        .heads_size = 0,
        .tails_size = 0,
    }
```

## EncodeBoolean
Encodes a boolean value according to the abi encoding specification.

### Signature

```zig
pub fn encodeBoolean(boolean: bool) [32]u8
```

## EncodeNumber
Encodes a integer value according to the abi encoding specification.

### Signature

```zig
pub fn encodeNumber(comptime T: type, number: T) [32]u8
```

## EncodeAddress
Encodes an solidity address value according to the abi encoding specification.

### Signature

```zig
pub fn encodeAddress(address: Address) [32]u8
```

## EncodeFixedBytes
Encodes an bytes1..32 value according to the abi encoding specification.

### Signature

```zig
pub fn encodeFixedBytes(comptime size: usize, payload: [size]u8) [32]u8
```

## EncodeString
Encodes an solidity string or bytes value according to the abi encoding specification.

### Signature

```zig
pub fn encodeString(allocator: Allocator, payload: []const u8) Allocator.Error![]u8
```

## EncodePacked
Encode values based on solidity's `encodePacked`.
Solidity types are infered from zig ones since it closely follows them.

Caller owns the memory and it must free them.

### Signature

```zig
pub fn encodePacked(allocator: Allocator, values: anytype) Allocator.Error![]u8
```

## IsDynamicType
Checks if a given parameter is a dynamic abi type.

### Signature

```zig
pub inline fn isDynamicType(comptime param: AbiParameter) bool
```

