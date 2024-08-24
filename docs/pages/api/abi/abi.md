## Abitype

### Properties

```zig
enum {
  function
  @"error"
  event
  constructor
  fallback
  receive
}
```

## Function

Solidity Abi function representation.\
Reference: ["function"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "function")
  /// Deprecated. Use either 'pure' or 'view'.
  ///
  /// https://github.com/ethereum/solidity/issues/992
  constant: ?bool = null
  /// Deprecated. Older vyper compiler versions used to provide gas estimates.
  ///
  /// https://github.com/vyperlang/vyper/issues/2151
  gas: ?i64 = null
  inputs: []const AbiParameter
  name: []const u8
  outputs: []const AbiParameter
  /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
  ///
  /// https://github.com/ethereum/solidity/issues/992
  payable: ?bool = null
  stateMutability: StateMutability
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: std.mem.Allocator) void
```

### Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiFunctionComptime` if the struct is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encode(self: @This(), allocator: Allocator, values: anytype) ![]u8
```

### EncodeOutputs
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `outputs` proprety.\
Caller owns the memory.\
Consider using `EncodeAbiFunctionComptime` if the struct is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encodeOutputs(self: @This(), allocator: Allocator, values: anytype) ![]u8
```

### Decode
Decode a encoded function based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiFunction` if the struct is
comptime know and you dont want to provided the return type.

### Signature

```zig
pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) !AbiDecoded(T)
```

### DecodeOutputs
Decode a encoded function based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `outputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiFunction` if the struct is
comptime know and you dont want to provided the return type.

### Signature

```zig
pub fn decodeOutputs(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) !AbiDecoded(T)
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

### AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

### Signature

```zig
pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8
```

### Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

### Signature

```zig
pub fn prepare(self: @This(), writer: anytype) !void
```

## Event

Solidity Abi function representation.\
Reference: ["event"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "event")
  name: []const u8
  inputs: []const AbiEventParameter
  anonymous: ?bool = null
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: std.mem.Allocator) void
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

### Encode
Encode the struct signature based it's hash.\
Caller owns the memory.\
Consider using `EncodeAbiEventComptime` if the struct is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encode(self: @This(), allocator: Allocator) !Hash
```

### EncodeLogTopics
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.

### Signature

```zig
pub fn encodeLogTopics(self: @This(), allocator: Allocator, values: anytype) ![]const ?Hash
```

### DecodeLogTopics
Decode the encoded log topics based on the event signature and the provided type.\
Caller owns the memory.

### Signature

```zig
pub fn decodeLogTopics(self: @This(), comptime T: type, encoded: []const ?Hash, options: LogDecoderOptions) !T
```

### AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

### Signature

```zig
pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8
```

### Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

### Signature

```zig
pub fn prepare(self: @This(), writer: anytype) !void
```

## Error

Solidity Abi function representation.\
Reference: ["error"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "error")
  name: []const u8
  inputs: []const AbiParameter
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: std.mem.Allocator) void
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

### Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiErrorComptime` if the struct is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encode(self: @This(), allocator: Allocator, values: anytype) ![]u8
```

### Decode
Decode a encoded error based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiError` if the struct is
comptime know and you dont want to provided the return type.

### Signature

```zig
pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) !AbiDecoded(T)
```

### AllocPrepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.\
Caller owns the memory.

### Signature

```zig
pub fn allocPrepare(self: @This(), allocator: Allocator) ![]u8
```

### Prepare
Format the struct into a human readable string.\
Intended to use for hashing purposes.

### Signature

```zig
pub fn prepare(self: @This(), writer: anytype) !void
```

## Constructor

Solidity Abi function representation.\
Reference: ["constructor"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "constructor")
  inputs: []const AbiParameter
  /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
  ///
  /// https://github.com/ethereum/solidity/issues/992
  payable: ?bool = null
  stateMutability: Extract(StateMutability, "payable,nonpayable")
}
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: std.mem.Allocator) void
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

### Encode
Encode the struct signature based on the values provided.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values
Caller owns the memory.\
Consider using `EncodeAbiConstructorComptime` if the struct is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encode(self: @This(), allocator: Allocator, values: anytype) !AbiEncoded
```

### Decode
Decode a encoded constructor arguments based on itself.\
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values.\
This methods will run the values against the `inputs` proprety.\
Caller owns the memory.\
Consider using `decodeAbiConstructor` if the struct is
comptime know and you dont want to provided the return type.

### Signature

```zig
pub fn decode(self: @This(), comptime T: type, allocator: Allocator, encoded: []const u8, options: DecodeOptions) !AbiDecoded(T)
```

## Fallback

Solidity Abi function representation.\
Reference: ["fallback"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "fallback")
  /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
  ///
  /// https://github.com/ethereum/solidity/issues/992
  payable: ?bool = null
  stateMutability: Extract(StateMutability, "payable,nonpayable")
}
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

## Receive

Solidity Abi function representation.\
Reference: ["receive"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)

### Properties

```zig
struct {
  type: Extract(Abitype, "receive")
  stateMutability: Extract(StateMutability, "payable")
}
```

### Format
Format the struct into a human readable string.

### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

## AbiItem

Union representing all of the possible Abi members.

### Properties

```zig
union(enum) {
  abiFunction: Function
  abiEvent: Event
  abiError: Error
  abiConstructor: Constructor
  abiFallback: Fallback
  abiReceive: Receive
}
```

### JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

### JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

### Deinit
### Signature

```zig
pub fn deinit(self: @This(), allocator: Allocator) void
```

### Format
### Signature

```zig
pub fn format(self: @This(), comptime layout: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void
```

## Abi

Abi representation in ZIG.

