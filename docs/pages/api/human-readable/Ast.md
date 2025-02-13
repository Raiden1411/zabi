## Offset

Offset used in the parser.

```zig
u32
```

## TokenIndex

Index used for the parser.

```zig
u32
```

## NodeList

Struct of arrays for the `Node` members.

```zig
std.MultiArrayList(Node)
```

## TokenList

Struct of arrays for the `Token.Tag` members.

```zig
std.MultiArrayList(struct {
    tag: TokenTag,
    start: Offset,
})
```

## Parse
Parses the source and build the Ast based on it.

### Signature

```zig
pub fn parse(
    allocator: Allocator,
    source: [:0]const u8,
) Parser.ParserErrors!Ast
```

## Deinit
Clears any allocated memory from the `Ast`.

### Signature

```zig
pub fn deinit(self: *Ast, allocator: Allocator) void
```

## FunctionProto
Build the ast representation for a `function_proto` node.

### Signature

```zig
pub fn functionProto(
    self: Ast,
    node: Node.Index,
) ast.FunctionDecl
```

## FunctionProtoOne
Build the ast representation for a `function_proto_one` node.

### Signature

```zig
pub fn functionProtoOne(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionDecl
```

## FunctionProtoMulti
Build the ast representation for a `function_proto_multi` node.

### Signature

```zig
pub fn functionProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.FunctionDecl
```

## FunctionProtoSimple
Build the ast representation for a `function_proto_simple` node.

### Signature

```zig
pub fn functionProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FunctionDecl
```

## ReceiveProto
Build the ast representation for a `receive_proto` node.

### Signature

```zig
pub fn receiveProto(
    self: Ast,
    node: Node.Index,
) ast.ReceiveDecl
```

## FallbackProtoMulti
Build the ast representation for a `fallback_proto_multi` node.

### Signature

```zig
pub fn fallbackProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.FallbackDecl
```

## FallbackProtoSimple
Build the ast representation for a `fallback_proto_simple` node.

### Signature

```zig
pub fn fallbackProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.FallbackDecl
```

## ConstructorProtoMulti
Build the ast representation for a `constructor_proto_multi` node.

### Signature

```zig
pub fn constructorProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.ConstructorDecl
```

## ConstructorProtoSimple
Build the ast representation for a `constructor_proto_simple` node.

### Signature

```zig
pub fn constructorProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ConstructorDecl
```

## EventProtoMulti
Build the ast representation for a `event_proto_multi` node.

### Signature

```zig
pub fn eventProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.EventDecl
```

## EventProtoSimple
Build the ast representation for a `event_proto_simple` node.

### Signature

```zig
pub fn eventProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.EventDecl
```

## ErrorProtoMulti
Build the ast representation for a `error_proto_multi` node.

### Signature

```zig
pub fn errorProtoMulti(
    self: Ast,
    node: Node.Index,
) ast.ErrorDecl
```

## ErrorProtoSimple
Build the ast representation for a `error_proto_simple` node.

### Signature

```zig
pub fn errorProtoSimple(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.ErrorDecl
```

## StructDecl
Build the ast representation for a `struct_decl` node.

### Signature

```zig
pub fn structDecl(
    self: Ast,
    node: Node.Index,
) ast.StructDecl
```

## StructDeclOne
Build the ast representation for a `struct_decl_one` node.

### Signature

```zig
pub fn structDeclOne(
    self: Ast,
    node_buffer: *[1]Node.Index,
    node: Node.Index,
) ast.StructDecl
```

## ExtraData
Converts the data in `extra_data` into `T`.

### Signature

```zig
pub fn extraData(
    self: Ast,
    comptime T: type,
    node: Node.Index,
) T
```

## FirstToken
Finds the first `TokenIndex` based on the provided node.

### Signature

```zig
pub fn firstToken(
    self: Ast,
    node: Node.Index,
) TokenIndex
```

## LastToken
Finds the last `TokenIndex` based on the provided node.

### Signature

```zig
pub fn lastToken(
    self: Ast,
    node: Node.Index,
) TokenIndex
```

## TokenSlice
Takes the associated token slice based on the provided token index.

### Signature

```zig
pub fn tokenSlice(
    self: Ast,
    token_index: TokenIndex,
) []const u8
```

## GetNodeSource
Gets the source code associated with the provided node.

### Signature

```zig
pub fn getNodeSource(
    self: Ast,
    node: Node.Index,
) []const u8
```

## ast

Ast representation of some of the "main" nodes.

### Properties

```zig
struct {
}
```

## ReceiveDecl

### Properties

```zig
struct {
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## FallbackDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## ConstructorDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## FunctionDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## ErrorDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
}
```

## EventDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
  anonymous: ?TokenIndex
}
```

## StructDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
}
```

## ReceiveDecl

### Properties

```zig
struct {
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## FallbackDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## ConstructorDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## FunctionDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
  view: ?TokenIndex
  pure: ?TokenIndex
  payable: ?TokenIndex
  public: ?TokenIndex
  external: ?TokenIndex
  virtual: ?TokenIndex
  override: ?TokenIndex
}
```

## ErrorDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
}
```

## EventDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
  anonymous: ?TokenIndex
}
```

## StructDecl

### Properties

```zig
struct {
  ast: ComponentDecl
  main_token: TokenIndex
  name: TokenIndex
}
```

## Node

Ast Node representation.

### Properties

```zig
struct {
  /// Associated tag of the node
  tag: Tag
  /// The node or token index of the `lhs` and `rhs` fields.
  data: Data
  /// The main token index associated with the node.
  main_token: TokenIndex
}
```

## Index

Index type into the slice.

```zig
u32
```

## Tag

Enum of all of the possible node tags.

### Properties

```zig
enum {
  root
  struct_type
  unreachable_node
  constructor_proto_simple
  constructor_proto_multi
  fallback_proto_simple
  fallback_proto_multi
  receive_proto
  event_proto_simple
  event_proto_multi
  error_proto_simple
  error_proto_multi
  function_proto
  function_proto_one
  function_proto_multi
  function_proto_simple
  array_type
  elementary_type
  tuple_type
  tuple_type_one
  specifiers
  struct_decl
  struct_decl_one
  struct_field
  var_decl
  error_var_decl
  event_var_decl
}
```

## Data

### Properties

```zig
struct {
  lhs: Index
  rhs: Index
}
```

## Range

### Properties

```zig
struct {
  start: Index
  end: Index
}
```

## FunctionProto

### Properties

```zig
struct {
  specifiers: Node.Index
  identifier: TokenIndex
  params_start: Node.Index
  params_end: Node.Index
}
```

## FunctionProtoOne

### Properties

```zig
struct {
  specifiers: Node.Index
  identifier: TokenIndex
  param: Node.Index
}
```

## FunctionProtoMulti

### Properties

```zig
struct {
  identifier: TokenIndex
  params_start: Node.Index
  params_end: Node.Index
}
```

## FunctionProtoSimple

### Properties

```zig
struct {
  identifier: TokenIndex
  param: Node.Index
}
```

## Index

Index type into the slice.

```zig
u32
```

## Tag

Enum of all of the possible node tags.

### Properties

```zig
enum {
  root
  struct_type
  unreachable_node
  constructor_proto_simple
  constructor_proto_multi
  fallback_proto_simple
  fallback_proto_multi
  receive_proto
  event_proto_simple
  event_proto_multi
  error_proto_simple
  error_proto_multi
  function_proto
  function_proto_one
  function_proto_multi
  function_proto_simple
  array_type
  elementary_type
  tuple_type
  tuple_type_one
  specifiers
  struct_decl
  struct_decl_one
  struct_field
  var_decl
  error_var_decl
  event_var_decl
}
```

## Data

### Properties

```zig
struct {
  lhs: Index
  rhs: Index
}
```

## Range

### Properties

```zig
struct {
  start: Index
  end: Index
}
```

## FunctionProto

### Properties

```zig
struct {
  specifiers: Node.Index
  identifier: TokenIndex
  params_start: Node.Index
  params_end: Node.Index
}
```

## FunctionProtoOne

### Properties

```zig
struct {
  specifiers: Node.Index
  identifier: TokenIndex
  param: Node.Index
}
```

## FunctionProtoMulti

### Properties

```zig
struct {
  identifier: TokenIndex
  params_start: Node.Index
  params_end: Node.Index
}
```

## FunctionProtoSimple

### Properties

```zig
struct {
  identifier: TokenIndex
  param: Node.Index
}
```

