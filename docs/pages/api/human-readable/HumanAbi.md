## HumanAbiErrors

Set of errors when converting to the abi

```zig
ParamErrors || Allocator.Error || error{ NoSpaceLeft, MissingTypeDeclaration }
```

## Errors

Set of erros when generating the ABI

```zig
HumanAbiErrors || Parser.ParserErrors || error{ UnexpectedMutability, UnexpectedNode }
```

## Parse
Parses the source, builds the Ast and generates the ABI.

It's recommend to use an `ArenaAllocator` for this.

### Signature

```zig
pub fn parse(arena: Allocator, source: [:0]const u8) Errors!Abi
```

## ToAbi
Generates the `Abi` from the ast nodes.

### Signature

```zig
pub fn toAbi(self: *HumanAbi) (HumanAbiErrors || error{ UnexpectedNode, UnexpectedMutability })!Abi
```

## ToAbiItem
Generates an `AbiItem` based on the provided node. Not all nodes are supported.

### Signature

```zig
pub fn toAbiItem(self: HumanAbi, node: Node.Index) (HumanAbiErrors || error{ UnexpectedNode, UnexpectedMutability })!AbiItem
```

## ToAbiFunction
Generates a `AbiFunction` from a `function_proto`.

### Signature

```zig
pub fn toAbiFunction(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiFunction
```

## ToAbiFunctionOne
Generates a `AbiFunction` from a `function_proto_one`.

### Signature

```zig
pub fn toAbiFunctionOne(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiFunction
```

## ToAbiFunctionMulti
Generates a `AbiFunction` from a `function_proto_multi`.

### Signature

```zig
pub fn toAbiFunctionMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiFunction
```

## ToAbiFunctionSimple
Generates a `AbiFunction` from a `function_proto_simple`.

### Signature

```zig
pub fn toAbiFunctionSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiFunction
```

## ToStructComponents
Generates a `AbiParameter` as a tuple with the components.

It gets generated from a `struct_decl` node.

### Signature

```zig
pub fn toStructComponents(self: HumanAbi, node: Node.Index) HumanAbiErrors![]const AbiParameter
```

## ToStructComponentsOne
Generates a `AbiParameter` as a tuple with the components.

It gets generated from a `struct_decl_one` node.

### Signature

```zig
pub fn toStructComponentsOne(self: HumanAbi, node: Node.Index) HumanAbiErrors![]const AbiParameter
```

## ToAbiConstructorMulti
Generates a `AbiConstructor` from a `constructor_proto_multi`.

### Signature

```zig
pub fn toAbiConstructorMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiConstructor
```

## ToAbiConstructorSimple
Generates a `AbiConstructor` from a `constructor_proto_simple`.

### Signature

```zig
pub fn toAbiConstructorSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiConstructor
```

## ToAbiEventMulti
Generates a `AbiEvent` from a `event_proto_multi`.

### Signature

```zig
pub fn toAbiEventMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEvent
```

## ToAbiEventSimple
Generates a `AbiEvent` from a `event_proto_simple`.

### Signature

```zig
pub fn toAbiEventSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEvent
```

## ToAbiErrorMulti
Generates a `AbiError` from a `error_proto_multi`.

### Signature

```zig
pub fn toAbiErrorMulti(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiError
```

## ToAbiErrorSimple
Generates a `AbiError` from a `error_proto_simple`.

### Signature

```zig
pub fn toAbiErrorSimple(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiError
```

## ToAbiParameters
Generates a `[]const AbiParameter` from a slice of `var_decl`.

### Signature

```zig
pub fn toAbiParameters(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiParameter
```

## ToAbiParametersFromDecl
Generates a `[]const AbiEventParameter` from a slice of `struct_field` or `error_var_decl`.

### Signature

```zig
pub fn toAbiParametersFromDecl(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiParameter
```

## ToAbiEventParameters
Generates a `[]const AbiEventParameter` from a slice of `event_var_decl`.

### Signature

```zig
pub fn toAbiEventParameters(self: HumanAbi, nodes: []const Node.Index) HumanAbiErrors![]const AbiEventParameter
```

## ToAbiParameter
Generates a `AbiParameter` from a `var_decl`.

### Signature

```zig
pub fn toAbiParameter(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiParameter
```

## ToAbiComponents
Generates a `[]const AbiParameter` or in other words generates the tuple components.

It is expecting the node to be a `tuple_type` or a `tuple_type_one`.

### Signature

```zig
pub fn toAbiComponents(self: HumanAbi, node: Node.Index) HumanAbiErrors![]const AbiParameter
```

## ToAbiEventParameter
Generates a `AbiEventParameter` from a `event_var_decl`.

### Signature

```zig
pub fn toAbiEventParameter(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiEventParameter
```

## ToAbiParameterFromDecl
Generates a `AbiParameter` from a `error_var_decl` or a `struct_field`.

### Signature

```zig
pub fn toAbiParameterFromDecl(self: HumanAbi, node: Node.Index) HumanAbiErrors!AbiParameter
```

## ToAbiFallbackMulti
Generates a `AbiFallback` from a `fallback_proto_multi`.

### Signature

```zig
pub fn toAbiFallbackMulti(self: HumanAbi, node: Node.Index) Allocator.Error!AbiFallback
```

## ToAbiFallbackSimple
Generates a `AbiFallback` from a `fallback_proto_simple`.

### Signature

```zig
pub fn toAbiFallbackSimple(self: HumanAbi, node: Node.Index) Allocator.Error!AbiFallback
```

## ToAbiReceive
Generates a `AbiReceive` from a `receive_proto`.

### Signature

```zig
pub fn toAbiReceive(self: HumanAbi, node: Node.Index) (Allocator.Error || error{UnexpectedMutability})!AbiReceive
```

