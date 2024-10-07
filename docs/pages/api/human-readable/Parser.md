## ParserErrors

Errors that can happing whilest parsing the source code.

```zig
error{ParsingError} || Allocator.Error
```

## Deinit
Clears any allocated memory.

### Signature

```zig
pub fn deinit(self: *Parser) void
```

## ParseSource
Parses all of the source and build the `Ast`.

### Signature

```zig
pub fn parseSource(self: *Parser) ParserErrors!void
```

## ParseUnits
Parsers all of the solidity source unit values.

More info can be found [here](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)

### Signature

```zig
pub fn parseUnits(self: *Parser) ParserErrors!Node.Range
```

## ExpectUnit
Expects to find a source unit otherwise it will fail.

### Signature

```zig
pub fn expectUnit(self: *Parser) ParserErrors!Node.Index
```

## ParseUnit
Parses a single source unit.

More info can be found [here](https://docs.soliditylang.org/en/latest/grammar.html#a4.SolidityParser.sourceUnit)

### Signature

```zig
pub fn parseUnit(self: *Parser) ParserErrors!Node.Index
```

## ParseFunctionProto
Parses a solidity function accordingly to the language grammar.

### Signature

```zig
pub fn parseFunctionProto(self: *Parser) ParserErrors!Node.Index
```

## ParseReceiveProto
Parses a solidity receive function accordingly to the language grammar.

### Signature

```zig
pub fn parseReceiveProto(self: *Parser) ParserErrors!Node.Index
```

## ParseFallbackProto
Parses a solidity fallback function accordingly to the language grammar.

### Signature

```zig
pub fn parseFallbackProto(self: *Parser) ParserErrors!Node.Index
```

## ParseConstructorProto
Parses a solidity constructor declaration accordingly to the language grammar.

### Signature

```zig
pub fn parseConstructorProto(self: *Parser) ParserErrors!Node.Index
```

## ParseSpecifiers
Parses all of the solidity mutability or visibility specifiers.

### Signature

```zig
pub fn parseSpecifiers(self: *Parser) ParserErrors!Node.Index
```

## ParseErrorProto
Parses a solidity error declaration accordingly to the language grammar.

### Signature

```zig
pub fn parseErrorProto(self: *Parser) ParserErrors!Node.Index
```

## ParseEventProto
Parses a solidity event declaration accordingly to the language grammar.

### Signature

```zig
pub fn parseEventProto(self: *Parser) ParserErrors!Node.Index
```

## ParseEventVarDecls
Parses the possible event declaration parameters according to the language grammar.

### Signature

```zig
pub fn parseEventVarDecls(self: *Parser) ParserErrors!Span
```

## ParseErrorVarDecls
Parses the possible error declaration parameters according to the language grammar.

### Signature

```zig
pub fn parseErrorVarDecls(self: *Parser) ParserErrors!Span
```

## ParseReturnParams
Parses the possible function declaration parameters according to the language grammar.

### Signature

```zig
pub fn parseReturnParams(self: *Parser) ParserErrors!Node.Range
```

## ParseVariableDecls
Parses the possible function declaration parameters according to the language grammar.

### Signature

```zig
pub fn parseVariableDecls(self: *Parser) ParserErrors!Span
```

## ExpectErrorVarDecl
Expects to find a `error_var_decl`. Otherwise returns an error.

### Signature

```zig
pub fn expectErrorVarDecl(self: *Parser) ParserErrors!Node.Index
```

## ParseErrorVarDecl
Parses the possible error declaration parameter according to the language grammar.

### Signature

```zig
pub fn parseErrorVarDecl(self: *Parser) ParserErrors!Node.Index
```

## ExpectEventVarDecl
Expects to find a `event_var_decl`. Otherwise returns an error.

### Signature

```zig
pub fn expectEventVarDecl(self: *Parser) ParserErrors!Node.Index
```

## ParseEventVarDecl
Parses the possible event declaration parameter according to the language grammar.

### Signature

```zig
pub fn parseEventVarDecl(self: *Parser) ParserErrors!Node.Index
```

## ExpectVarDecl
Expects to find a `var_decl`. Otherwise returns an error.

### Signature

```zig
pub fn expectVarDecl(self: *Parser) ParserErrors!Node.Index
```

## ParseVariableDecl
Parses the possible function declaration parameter according to the language grammar.

### Signature

```zig
pub fn parseVariableDecl(self: *Parser) ParserErrors!Node.Index
```

## ParseStructDecl
Parses a struct declaration according to the language grammar.

### Signature

```zig
pub fn parseStructDecl(self: *Parser) ParserErrors!Node.Index
```

## ParseStructFields
Parses all of the structs fields according to the language grammar.

### Signature

```zig
pub fn parseStructFields(self: *Parser) ParserErrors!Span
```

## ExpectStructField
Expects to find a struct parameter or fails.

### Signature

```zig
pub fn expectStructField(self: *Parser) ParserErrors!Node.Index
```

## ExpectType
Expects to find either a `elementary_type`, `tuple_type`, `tuple_type_one`, `array_type` or `struct_type`

### Signature

```zig
pub fn expectType(self: *Parser) ParserErrors!Node.Index
```

## ParseType
Parses the token into either a `elementary_type`, `tuple_type`, `tuple_type_one`, `array_type` or `struct_type`

### Signature

```zig
pub fn parseType(self: *Parser) ParserErrors!Node.Index
```

## ParseTupleType
Parses the tuple type similarly to `parseErrorVarDecls`.

### Signature

```zig
pub fn parseTupleType(self: *Parser) ParserErrors!Node.Index
```

## ConsumeElementaryType
Creates a `elementary_type` node based on the solidity type keywords.

### Signature

```zig
pub fn consumeElementaryType(self: *Parser) Allocator.Error!Node.Index
```

