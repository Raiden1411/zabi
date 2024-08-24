## TokenList

```zig
std.MultiArrayList(struct {
    token_type: Tokens,
    start: u32,
    end: u32,
})
```

## ParseError

```zig
error{ InvalidDataLocation, UnexceptedToken, InvalidType, ExpectedCommaAfterParam, EmptyReturnParams } || ParamErrors
```

## ParseAbiProto
Parse a string or a multi line string with solidity signatures.\
This will return all signatures as a slice of `AbiItem`.\
This supports parsing struct signatures if its intended to use
The struct signatures must be defined top down.

### Signature

```zig
pub fn parseAbiProto(p: *Parser) !Abi
```

## ParseAbiItemProto
### Signature

```zig
pub fn parseAbiItemProto(p: *Parser) !AbiItem
```

## ParseFunctionFnProto
### Signature

```zig
pub fn parseFunctionFnProto(p: *Parser) !Function
```

## ParseEventFnProto
### Signature

```zig
pub fn parseEventFnProto(p: *Parser) !Event
```

## ParseErrorFnProto
### Signature

```zig
pub fn parseErrorFnProto(p: *Parser) !Error
```

## ParseConstructorFnProto
### Signature

```zig
pub fn parseConstructorFnProto(p: *Parser) !Constructor
```

## ParseStructProto
### Signature

```zig
pub fn parseStructProto(p: *Parser) !void
```

## ParseFallbackFnProto
### Signature

```zig
pub fn parseFallbackFnProto(p: *Parser) !Fallback
```

## ParseReceiveFnProto
### Signature

```zig
pub fn parseReceiveFnProto(p: *Parser) !Receive
```

## ParseFuncParamsDecl
### Signature

```zig
pub fn parseFuncParamsDecl(p: *Parser) ![]const AbiParameter
```

## ParseEventParamsDecl
### Signature

```zig
pub fn parseEventParamsDecl(p: *Parser) ![]const AbiEventParameter
```

