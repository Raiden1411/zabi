## TxPoolStatus

Result tx pool status.

### Properties

```zig
pending: u64
queued: u64
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

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

## JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

## JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## TxPoolContent

Result tx pool content.

### Properties

```zig
pending: Subpool
queued: Subpool
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

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

## JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

## JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## TxPoolInspect

### Properties

```zig
pending: InspectSubpool
queued: InspectSubpool
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

### JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## JsonParse
### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This()
```

## JsonParseFromValue
### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This()
```

## JsonStringify
### Signature

```zig
pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void
```

## Subpool

Geth mempool subpool type

### Properties

```zig
address: AddressHashMap
```

### JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!Subpool
```

### JsonStringify
Address are checksumed on stringify.

### Signature

```zig
pub fn jsonStringify(value: Subpool, source: anytype) !void
```

### JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!Subpool
```

## JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!Subpool
```

## JsonStringify
Address are checksumed on stringify.

### Signature

```zig
pub fn jsonStringify(value: Subpool, source: anytype) !void
```

## JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!Subpool
```

## InspectSubpool

Geth mempool inspect subpool type

### Properties

```zig
address: InspectAddressHashMap
```

### JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!InspectSubpool
```

### JsonStringify
Address are checksumed on stringify.

### Signature

```zig
pub fn jsonStringify(value: InspectSubpool, source: anytype) !void
```

### JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!InspectSubpool
```

## JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!InspectSubpool
```

## JsonStringify
Address are checksumed on stringify.

### Signature

```zig
pub fn jsonStringify(value: InspectSubpool, source: anytype) !void
```

## JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!InspectSubpool
```

## InspectPoolTransactionByNonce

Geth inspect transaction object dump from mempool by nonce.

### Properties

```zig
nonce: InspectPoolPendingTransactionHashMap
```

### JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!InspectPoolTransactionByNonce
```

### JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!InspectPoolTransactionByNonce
```

### JsonStringify
Converts the nonces into strings.

### Signature

```zig
pub fn jsonStringify(value: InspectPoolTransactionByNonce, source: anytype) !void
```

## JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!InspectPoolTransactionByNonce
```

## JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!InspectPoolTransactionByNonce
```

## JsonStringify
Converts the nonces into strings.

### Signature

```zig
pub fn jsonStringify(value: InspectPoolTransactionByNonce, source: anytype) !void
```

## PoolTransactionByNonce

Geth transaction object dump from mempool by nonce.

### Properties

```zig
nonce: PoolPendingTransactionHashMap
```

### JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!PoolTransactionByNonce
```

### JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!PoolTransactionByNonce
```

### JsonStringify
Converts the nonces into strings.

### Signature

```zig
pub fn jsonStringify(value: PoolTransactionByNonce, source: anytype) !void
```

## JsonParse
Parses as a dynamic value and then uses that value to json parse

### Signature

```zig
pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!PoolTransactionByNonce
```

## JsonParseFromValue
Uses similar approach as `jsonParse` but the value is already pre parsed from
a dynamic `Value`

### Signature

```zig
pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!PoolTransactionByNonce
```

## JsonStringify
Converts the nonces into strings.

### Signature

```zig
pub fn jsonStringify(value: PoolTransactionByNonce, source: anytype) !void
```

