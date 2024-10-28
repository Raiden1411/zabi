## Token

Token structure produced my the tokenizer.

### Properties

```zig
struct {
  token: Tag
  location: Location
}
```

## Location

### Properties

```zig
struct {
  start: usize
  end: usize
}
```

## Tag

### Properties

```zig
enum {
  identifier
  value
  value_int
  eof
  invalid
}
```

## Location

### Properties

```zig
struct {
  start: usize
  end: usize
}
```

## Tag

### Properties

```zig
enum {
  identifier
  value
  value_int
  eof
  invalid
}
```

## Offset

Index used to know token starts and ends.

```zig
u32
```

## TokenIndex

Index used to know token tags.

```zig
u32
```

## TokenList

MultiArrayList used to generate the neccessary information for the parser to use.

```zig
std.MultiArrayList(struct {
    tag: Token.Tag,
    start: Offset,
})
```

## Tokenizer

Tokenizer that will produce lexicar tokens so that the
parser can consume and load it to the `EnvMap`.

### Properties

```zig
struct {
  /// The source that will be used to produce tokens.
  buffer: [:0]const u8
  /// Current index into the source
  index: usize
}
```

### Init
Sets the initial state.

### Signature

```zig
pub fn init(source: [:0]const u8) Tokenizer
```

### Next
Advances the tokenizer's state and produces a single token.

### Signature

```zig
pub fn next(self: *Tokenizer) Token
```

## ParserEnv

Parses the enviroment variables strings and loads them
into a `EnvMap`.

### Properties

```zig
struct {
  /// Slice of produced token tags from the tokenizer.
  token_tags: []const Token.Tag
  /// Slice of produced token starts from the tokenizer.
  token_starts: []const Offset
  /// The current index in any of the previous slices.
  token_index: TokenIndex
  /// The source that will be used to load values from.
  source: [:0]const u8
  /// The enviroment map that will be used to load the variables to.
  env_map: *EnvMap
}
```

### ParseAndLoad
Parses all token tags and loads the all into the `EnvMap`.

### Signature

```zig
pub fn parseAndLoad(self: *ParserEnv) !void
```

### ParseAndLoadOne
Parses a single line and load it to memory.
IDENT -> VALUE/VALUE_INT

### Signature

```zig
pub fn parseAndLoadOne(self: *ParserEnv) (Allocator.Error || error{UnexpectedToken})!void
```

### ParseIdentifier
Parses the identifier token.
Returns and error if the current token is not a `identifier` one.

### Signature

```zig
pub fn parseIdentifier(self: *ParserEnv) error{UnexpectedToken}!TokenIndex
```

### ParseIntValue
Parses the value_int token.
Returns null if the current token is not a `value_int` one.

### Signature

```zig
pub fn parseIntValue(self: *ParserEnv) ?TokenIndex
```

### ParseValue
Parses the value or value_int token.
Returns and error if the current token is not a `value` or `value_int` one.

### Signature

```zig
pub fn parseValue(self: *ParserEnv) error{UnexpectedToken}!TokenIndex
```

## ParseToEnviromentVariables
Parses and loads all possible enviroment variables from the
provided `source`.

Can error if the parser encounters unexpected token values.

### Signature

```zig
pub fn parseToEnviromentVariables(
    allocator: Allocator,
    source: [:0]const u8,
    env_map: *EnvMap,
) (Allocator.Error || error{UnexpectedToken})!void
```

