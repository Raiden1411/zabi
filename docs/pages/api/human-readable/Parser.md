## TokenList

```zig
std.MultiArrayList(struct {
    token_type: Tokens,
    start: u32,
    end: u32,
})
```

## ParseErrors

Set of possible errors that can happen while parsing.

```zig
error{
    InvalidDataLocation,
    UnexceptedToken,
    InvalidType,
    ExpectedCommaAfterParam,
    EmptyReturnParams,
} || ParamErrors || Allocator.Error
```

## ParseAbiProto
Parse a string or a multi line string with solidity signatures.\
This will return all signatures as a slice of `AbiItem`.

This supports parsing struct signatures if its intended to use
The struct signatures must be defined top down.

**Example**
```zig
var lex = Lexer.init(source);

var list = Parser.TokenList{};
defer list.deinit(allocator);

while (true) {
    const tok = lex.scan();

    try list.append(allocator, .{
        .token_type = tok.syntax,
        .start = tok.location.start,
        .end = tok.location.end,
    });

    if (tok.syntax == .EndOfFileToken) break;
}

var parser: Parser = .{
    .alloc = allocator,
    .tokens = list.items(.token_type),
    .tokens_start = list.items(.start),
    .tokens_end = list.items(.end),
    .token_index = 0,
    .source = source,
    .structs = .{},
};

const abi = try parser.parseAbiProto();
```

### Signature

```zig
pub fn parseAbiProto(p: *Parser) ParseErrors!Abi
```

## ParseAbiItemProto
Parse a single solidity signature based on expected tokens.

Will return an error if the token is not expected.

### Signature

```zig
pub fn parseAbiItemProto(p: *Parser) ParseErrors!AbiItem
```

## ParseFunctionFnProto
Parse single solidity function signature.\
FunctionProto -> Function KEYWORD, Identifier, OpenParen, ParamDecls?, ClosingParen, Visibility?, StateMutability?, Returns?

### Signature

```zig
pub fn parseFunctionFnProto(p: *Parser) ParseErrors!Function
```

## ParseEventFnProto
Parse single solidity event signature.\
EventProto -> Event KEYWORD, Identifier, OpenParen, ParamDecls?, ClosingParen

### Signature

```zig
pub fn parseEventFnProto(p: *Parser) ParseErrors!Event
```

## ParseErrorFnProto
Parse single solidity error signature.\
ErrorProto -> Error KEYWORD, Identifier, OpenParen, ParamDecls?, ClosingParen

### Signature

```zig
pub fn parseErrorFnProto(p: *Parser) ParseErrors!Error
```

## ParseConstructorFnProto
Parse single solidity constructor signature.\
ConstructorProto -> Constructor KEYWORD, OpenParen, ParamDecls?, ClosingParen, StateMutability?

### Signature

```zig
pub fn parseConstructorFnProto(p: *Parser) ParseErrors!Constructor
```

## ParseStructProto
Parse single solidity struct signature.\
StructProto -> Struct KEYWORD, Identifier, OpenBrace, ParamDecls, ClosingBrace

### Signature

```zig
pub fn parseStructProto(p: *Parser) ParseErrors!void
```

## ParseFallbackFnProto
Parse single solidity fallback signature.\
FallbackProto -> Fallback KEYWORD, OpenParen, ClosingParen, StateMutability?

### Signature

```zig
pub fn parseFallbackFnProto(p: *Parser) error{UnexceptedToken}!Fallback
```

## ParseReceiveFnProto
Parse single solidity receive signature.\
ReceiveProto -> Receive KEYWORD, OpenParen, ClosingParen, External, Payable

### Signature

```zig
pub fn parseReceiveFnProto(p: *Parser) error{UnexceptedToken}!Receive
```

## ParseFuncParamsDecl
Parse solidity function params.\
TypeExpr, DataLocation?, Identifier?, Comma?

### Signature

```zig
pub fn parseFuncParamsDecl(p: *Parser) ParseErrors![]const AbiParameter
```

## ParseEventParamsDecl
Parse solidity event params.\
TypeExpr, DataLocation?, Identifier?, Comma?

### Signature

```zig
pub fn parseEventParamsDecl(p: *Parser) ParseErrors![]const AbiEventParameter
```

## ParseErrorParamsDecl
Parse solidity error params.\
TypeExpr, DataLocation?, Identifier?, Comma?

### Signature

```zig
pub fn parseErrorParamsDecl(p: *Parser) ParseErrors![]const AbiParameter
```

## ParseStructParamDecls
Parse solidity struct params.\
TypeExpr, Identifier?, SemiColon

### Signature

```zig
pub fn parseStructParamDecls(p: *Parser) ParseErrors![]const AbiParameter
```

## ParseTuple
Parse solidity tuple params.\
OpenParen, TypeExpr, Identifier?, Comma?, ClosingParen

### Signature

```zig
pub fn parseTuple(p: *Parser, comptime T: type) ParseErrors!T
```

