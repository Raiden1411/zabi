# ZAbi
Handle, generate, encode and decode Solidity ABI's using the Zig. 

## Status
This is pre-1.0 software. Although breaking changes are less frequent with each minor version release,
they will still occur until we reach 1.0.

## Zig Version
The main branch follows Zig's master branch, which is the latest dev version of Zig. There will also be 
branches and tags that will work with the previous two (2) stable Zig releases.

## Integrating ZAbi in your Project
### Zig Package Manager
In the `build.zig.zon` file, add the following to the dependencies object.

```zig
.ziglyph = .{
    .url = "https://github.com/Raiden1411/zabi/archive/VERSION_NUMBER.tar.gz",
}
```

The compiler will produce a hash mismatch error, add the `.hash` field to `build.zig.zon`
with the hash the compiler tells you it found.

Then in your `build.zig` file add the following to the `exe` section for the executable where you wish to have ZAbi available.

```zig
const ziglyph = b.dependency("zabi", .{
    .optimize = optimize,
    .target = target,
});
// for exe, lib, tests, etc.
exe.addModule("zabi", ziglyph.module("zabi"));
```

Now in the code, you can import components like this:

```zig
const zabi = @import("zabi");
const meta = zabi.meta;
const encoder = zabi.encoder;
```

### Using `ZAbi`

With zabi you can quick parse your json ABI's into the struct representation in Zig.

Bellow you will see an example for parsing AbiParameters.

```zig
test "Json parse with multiple components" {
    const zabi = @import("zabi");
    const AbiParameter = zabi.param.AbiParameter;
    const ParamType = zabi.param_type.ParamType;

    const slice =
        \\ {
        \\  "name": "foo",
        \\  "type": "tuple",
        \\  "components": [
        \\      {
        \\          "type": "address",
        \\          "name": "bar"
        \\      },
        \\      {
        \\          "type": "int",
        \\          "name": "baz"
        \\      }
        \\  ]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(AbiParameter, testing.allocator, slice, .{});
    defer parsed.deinit();

    try testing.expect(null == parsed.value.internalType);
    try testing.expectEqual(ParamType{ .tuple = {} }, parsed.value.type);
    try testing.expectEqual(ParamType{ .address = {} }, parsed.value.components.?[0].type);
    try testing.expectEqual(ParamType{ .int = 256 }, parsed.value.components.?[1].type);
    try testing.expectEqualStrings("foo", parsed.value.name);
    try testing.expectEqualStrings("bar", parsed.value.components.?[0].name);
    try testing.expectEqualStrings("baz", parsed.value.components.?[1].name);
}

```

This works also with all of the defined types in `abi.zig`

### Human readable

With zabi you are also able to define these struct using solidity syntax.

Here is an example of how to accomplish this.

```zig
test "Abi with nested struct" {
    const zabi = @import("zabi");
    const abi = zabi.abi;
    const ParamType = zabi.param_type.ParamType;

    const slice =
        \\struct Foo {address bar; string baz;}
        \\struct Bar {Foo foo;}
        \\function Fizz(Bar bar) public pure returns (Foo foo)
    ;

    const signature = try parseHumanReadable(abi.Abi, testing.allocator, slice);
    defer signature.deinit();

    const function = signature.value[0].abiFunction;
    try testing.expectEqual(function.type, .function);
    try testing.expectEqualStrings("Fizz", function.name);
    try testing.expectEqual(ParamType{ .tuple = {} }, function.inputs[0].type);
    try testing.expectEqualStrings("bar", function.inputs[0].name);
    try testing.expectEqual(ParamType{ .tuple = {} }, function.inputs[0].components.?[0].type);
    try testing.expectEqualStrings("foo", function.inputs[0].components.?[0].name);
    try testing.expectEqual(ParamType{ .address = {} }, function.inputs[0].components.?[0].components.?[0].type);
    try testing.expectEqual(ParamType{ .string = {} }, function.inputs[0].components.?[0].components.?[1].type);
    try testing.expectEqualStrings("bar", function.inputs[0].components.?[0].components.?[0].name);
    try testing.expectEqualStrings("baz", function.inputs[0].components.?[0].components.?[1].name);
    try testing.expectEqual(function.stateMutability, .pure);
    try testing.expectEqual(ParamType{ .address = {} }, function.outputs[0].components.?[0].type);
    try testing.expectEqual(ParamType{ .string = {} }, function.outputs[0].components.?[1].type);
    try testing.expectEqualStrings("bar", function.outputs[0].components.?[0].name);
    try testing.expectEqualStrings("baz", function.outputs[0].components.?[1].name);
}
```

ZAbi human readable parsing fully supports all feature that you would expect it to. From tuple to structs to even parsing the Seaport Opensea contract. \
Slices must be defined as either a single string or a multi line string.
Struct parsing is only supported currently if you are passing the `Abi` type to the `parseHumanReadable` method.

### Encoding

Zabi also fully supports abi encoding of parameters to all signature types.

Here is an example of how to accomplish this.

```zig
const sig = try human.parseHumanReadable(abi.Error, testing.allocator, "error Foo(bool foo, string bar)");
defer sig.deinit();

const encoded = try sig.value.encode(testing.allocator, .{ true, "fizzbuzz" });
defer testing.allocator.free(encoded);

try testing.expectEqualStrings("65c9c0c100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000866697a7a62757a7a000000000000000000000000000000000000000000000000", encoded);
```

You can use the encoder in two ways. If the struct is either comptime know or not. The example above show you how you can use it if the signature is not comptime know. However you can use the comptime methods if you know the struct format in advance. By using those methods you will gain access to type safe parameters.

### Decoding

ZAbi can also decode abi parameters/signatures. Currently it only supports comptime know parameters or signatures.

```zig
const decoded = try decodeAbiFunction(testing.allocator, .{ .type = .function, .name = "Bar", .inputs = &.{.{ .type = .{ .string = {} }, .name = "foo" }}, .stateMutability = .nonpayable, .outputs = &.{} }, "4ec7c7ae00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000");
defer decoded.deinit();

try testInnerValues(.{"foo"}, decoded.values);
try testing.expectEqualStrings("0x4ec7c7ae", decoded.name);
```

These are just some of the things that zabi can do. We also have some meta programing functions for you to use as well as some other utilites functions that might be usefull for your development journey.

### Sponsors

If you find ZAbi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411). Thank you 🙏

### Contributing

Contributions to ZAbi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix.
