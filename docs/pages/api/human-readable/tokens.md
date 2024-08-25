## Tag

Tokens tags consumedd by the Lexer

### Properties

```zig
struct {
  syntax: SoliditySyntax
  location: Location
}
```

## Location

### Properties

```zig
struct {
  start: u32
  end: u32
}
```

### TypesKeyword
### Signature

```zig
pub fn typesKeyword(identifier: []const u8) ?SoliditySyntax
```

### Keywords
### Signature

```zig
pub fn keywords(identifier: []const u8) ?SoliditySyntax
```

## SoliditySyntax

### Properties

```zig
enum {
  Identifier
  Number
  Public
  External
  View
  Payable
  Pure
  Private
  Internal
  Function
  Event
  Error
  Fallback
  Receive
  Constructor
  Calldata
  Memory
  Storage
  Indexed
  Comma
  SemiColon
  OpenParen
  ClosingParen
  OpenBrace
  ClosingBrace
  OpenBracket
  ClosingBracket
  After
  Alias
  Anonymous
  Apply
  Auto
  Byte
  Case
  Catch
  Constant
  Copyof
  Default
  Defined
  False
  Final
  Immutable
  Implements
  In
  Inline
  Let
  Mapping
  Match
  Mutable
  Null
  Of
  Override
  Partial
  Promise
  Reference
  Relocatable
  Return
  Returns
  Sizeof
  Static
  Struct
  Super
  Supports
  Switch
  This
  True
  Try
  Typedef
  Typeof
  Var
  Virtual
  Address
  Bool
  Tuple
  String
  Bytes
  Bytes1
  Bytes2
  Bytes3
  Bytes4
  Bytes5
  Bytes6
  Bytes7
  Bytes8
  Bytes9
  Bytes10
  Bytes11
  Bytes12
  Bytes13
  Bytes14
  Bytes15
  Bytes16
  Bytes17
  Bytes18
  Bytes19
  Bytes20
  Bytes21
  Bytes22
  Bytes23
  Bytes24
  Bytes25
  Bytes26
  Bytes27
  Bytes28
  Bytes29
  Bytes30
  Bytes31
  Bytes32
  Uint
  Uint8
  Uint16
  Uint24
  Uint32
  Uint40
  Uint48
  Uint56
  Uint64
  Uint72
  Uint80
  Uint88
  Uint96
  Uint104
  Uint112
  Uint120
  Uint128
  Uint136
  Uint144
  Uint152
  Uint160
  Uint168
  Uint176
  Uint184
  Uint192
  Uint200
  Uint208
  Uint216
  Uint224
  Uint232
  Uint240
  Uint248
  Uint256
  Int
  Int8
  Int16
  Int24
  Int32
  Int40
  Int48
  Int56
  Int64
  Int72
  Int80
  Int88
  Int96
  Int104
  Int112
  Int120
  Int128
  Int136
  Int144
  Int152
  Int160
  Int168
  Int176
  Int184
  Int192
  Int200
  Int208
  Int216
  Int224
  Int232
  Int240
  Int248
  Int256
  EndOfFileToken
  UnknowToken
}
```

### LexProtectedKeywords
### Signature

```zig
pub fn lexProtectedKeywords(tok_type: SoliditySyntax) ?[]const u8
```

### LexToken
### Signature

```zig
pub fn lexToken(tok_type: SoliditySyntax) ?[]const u8
```

## Location

### Properties

```zig
struct {
  start: u32
  end: u32
}
```

## SoliditySyntax

### Properties

```zig
enum {
  Identifier
  Number
  Public
  External
  View
  Payable
  Pure
  Private
  Internal
  Function
  Event
  Error
  Fallback
  Receive
  Constructor
  Calldata
  Memory
  Storage
  Indexed
  Comma
  SemiColon
  OpenParen
  ClosingParen
  OpenBrace
  ClosingBrace
  OpenBracket
  ClosingBracket
  After
  Alias
  Anonymous
  Apply
  Auto
  Byte
  Case
  Catch
  Constant
  Copyof
  Default
  Defined
  False
  Final
  Immutable
  Implements
  In
  Inline
  Let
  Mapping
  Match
  Mutable
  Null
  Of
  Override
  Partial
  Promise
  Reference
  Relocatable
  Return
  Returns
  Sizeof
  Static
  Struct
  Super
  Supports
  Switch
  This
  True
  Try
  Typedef
  Typeof
  Var
  Virtual
  Address
  Bool
  Tuple
  String
  Bytes
  Bytes1
  Bytes2
  Bytes3
  Bytes4
  Bytes5
  Bytes6
  Bytes7
  Bytes8
  Bytes9
  Bytes10
  Bytes11
  Bytes12
  Bytes13
  Bytes14
  Bytes15
  Bytes16
  Bytes17
  Bytes18
  Bytes19
  Bytes20
  Bytes21
  Bytes22
  Bytes23
  Bytes24
  Bytes25
  Bytes26
  Bytes27
  Bytes28
  Bytes29
  Bytes30
  Bytes31
  Bytes32
  Uint
  Uint8
  Uint16
  Uint24
  Uint32
  Uint40
  Uint48
  Uint56
  Uint64
  Uint72
  Uint80
  Uint88
  Uint96
  Uint104
  Uint112
  Uint120
  Uint128
  Uint136
  Uint144
  Uint152
  Uint160
  Uint168
  Uint176
  Uint184
  Uint192
  Uint200
  Uint208
  Uint216
  Uint224
  Uint232
  Uint240
  Uint248
  Uint256
  Int
  Int8
  Int16
  Int24
  Int32
  Int40
  Int48
  Int56
  Int64
  Int72
  Int80
  Int88
  Int96
  Int104
  Int112
  Int120
  Int128
  Int136
  Int144
  Int152
  Int160
  Int168
  Int176
  Int184
  Int192
  Int200
  Int208
  Int216
  Int224
  Int232
  Int240
  Int248
  Int256
  EndOfFileToken
  UnknowToken
}
```

### LexProtectedKeywords
### Signature

```zig
pub fn lexProtectedKeywords(tok_type: SoliditySyntax) ?[]const u8
```

### LexToken
### Signature

```zig
pub fn lexToken(tok_type: SoliditySyntax) ?[]const u8
```

