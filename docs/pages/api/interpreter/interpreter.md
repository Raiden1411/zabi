# EVM Interpreter

## Definition

Zabi provides a implementation of an EVM interpreter. This can be used to run any bytecode in the context of the Interpreter.

This is not the full virtual machine but it can be used regardless. You can also use the Interpreter to fully build the EVM if you would like.

You can checkout our [examples](https://github.com/Raiden1411/zabi/blob/main/examples/interpreter/interpreter.zig) to get a better idea on how to run it.
Every member of the interpreter is exposed in the library including the stack and the expandable memory used by it.

## Usage

To use the interpreter you will need a `Contract` instance, a `Host` interface and ofcourse and `Allocator`.

The `Contract` instance represent the bytecode and the caller and target addresses it needs to run against.
The `Host` is an interface that needs to be implementented by an EVM Host so that some of the opcodes that need this are allowed to run successfully.

## Example

```zig
var interpreter: Interpreter = undefined;
defer interpreter.deinit();

try interpreter.init(gpa.allocator(), contract_instance, plain.host(), .{});

const result = try interpreter.run();

std.debug.print("Interpreter result: {any}", .{result});
```

