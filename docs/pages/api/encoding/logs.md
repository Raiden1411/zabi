## EncodeLogsErrors

Set of errors while performing logs abi encoding.

```zig
Allocator.Error || error{NoSpaceLeft}
```

## EncodeLogTopicsFromReflection
Performs compile time reflection to decided on which way to encode the values.
Uses the [specification](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding) as the base of encoding.

Bellow you will find the list of all supported types and what will they be encoded as.

  * Zig `bool` -> Will be encoded like a boolean value
  * Zig `?T` -> Encodes the values if not null otherwise it appends the null value to the topics.
  * Zig `int`, `comptime_int` -> Will be encoded based on the signedness of the integer.
  * Zig `[N]u8` -> Only support max size of 32. All are encoded as little endian. If you need to use `[20]u8` for address
                   please consider encoding as a `u160` and then `@bitCast` that value to an `[20]u8` array.
  * Zig `enum`, `enum_literal` -> The tagname of the enum encoded as a string/bytes value.
  * Zig `*T` -> will encoded the child type. If the child type is an `array` it will encode as string/bytes.
  * Zig `[]const u8`, `[]u8` -> Will encode according the string/bytes specification.

All other types are currently not supported.

### Signature

```zig
pub fn encodeLogTopicsFromReflection(
    allocator: Allocator,
    event: AbiEvent,
    values: anytype,
) EncodeLogsErrors![]const ?Hash
```

## EncodeLogTopics
Encodes the values based on the [specification](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding)

Most of solidity types are supported, only `fixedArray`, `dynamicArray` and `tuples`
are not supported. These are quite niche and in previous version of zabi they were supported.

However I don't see the benifit of supporting them anymore. If the need arises in the future
this will be added again. But for now this as been disabled.

### Signature

```zig
pub fn encodeLogTopics(
    comptime event: AbiEvent,
    allocator: Allocator,
    values: AbiEventParametersDataToPrimative(event.inputs),
) Allocator.Error![]const ?Hash
```

## AbiLogTopicsEncoderReflection

Structure used to encode event log topics based on the [specification](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding)

### Properties

```zig
struct {
  /// List of encoded log topics.
  topics: ArrayListUnmanaged(?Hash)
}
```

## empty

Initializes the structure.

```zig
.{
        .topics = .empty,
    }
```

### EncodeLogTopicsWithSignature
Generates the signature hash from the provided event and appends it to the `topics`.

If the event inputs are of length 0 it will return the slice with just that hash.
For more details please checkout `encodeLogTopicsFromReflection`.

### Signature

```zig
pub fn encodeLogTopicsWithSignature(
    self: *Self,
    allocator: Allocator,
    event: AbiEvent,
    values: anytype,
) EncodeLogsErrors![]const ?Hash
```

### EncodeLogTopics
Performs compile time reflection to decided on which way to encode the values.
Uses the [specification](https://docs.soliditylang.org/en/latest/abi-spec.html#indexed-event-encoding) as the base of encoding.

Bellow you will find the list of all supported types and what will they be encoded as.

  * Zig `bool` -> Will be encoded like a boolean value
  * Zig `?T` -> Encodes the values if not null otherwise it appends the null value to the topics.
  * Zig `int`, `comptime_int` -> Will be encoded based on the signedness of the integer.
  * Zig `[N]u8` -> Only support max size of 32. All are encoded as little endian. If you need to use `[20]u8` for address
                   please consider encoding as a `u160` and then `@bitCast` that value to an `[20]u8` array.
  * Zig `enum`, `enum_literal` -> The tagname of the enum encoded as a string/bytes value.
  * Zig `*T` -> will encoded the child type. If the child type is an `array` it will encode as string/bytes.
  * Zig `[]const u8`, `[]u8` -> Will encode according the string/bytes specification.

All other types are currently not supported.

### Signature

```zig
pub fn encodeLogTopics(
    self: *Self,
    allocator: Allocator,
    values: anytype,
) Allocator.Error![]const ?Hash
```

### EncodeLogTopic
Uses compile time reflection to decide how to encode the value.

For more information please checkout `AbiLogTopicsEncoderReflection.encodeLogTopics` or `encodeLogTopicsFromReflection`.

### Signature

```zig
pub fn encodeLogTopic(self: *Self, value: anytype) void
```

## empty

Initializes the structure.

```zig
.{
        .topics = .empty,
    }
```

## AbiLogTopicsEncoder
Generates a structure based on the provided `event`.

This generates the event hash as well as the indexed parameters used by `encodeLogTopics`.

### Signature

```zig
pub fn AbiLogTopicsEncoder(comptime event: AbiEvent) type
```

## empty

Initialize the structure.

```zig
.{
            .topics = .empty,
        }
```

