<br/>

<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Raiden1411/zabi/main/.github/zabi.svg">
      <img alt="ZAbi logo" src="https://raw.githubusercontent.com/Raiden1411/zabi/main/.github/zabi.svg" width="auto" height="150">
    </picture>
</p>

<p align="center">
  Interact with ethereum via Zig!
<p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://codecov.io/github/Raiden1411/zabi/graph/badge.svg">
    <img alt="ZAbi logo" src="https://codecov.io/github/Raiden1411/zabi/graph/badge.svg" width="auto" height="25">
  </picture>
<p>

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
.zabi = .{
    .url = "https://github.com/Raiden1411/zabi/archive/VERSION_NUMBER.tar.gz",
}
```

The compiler will produce a hash mismatch error, add the `.hash` field to `build.zig.zon`
with the hash the compiler tells you it found.

Then in your `build.zig` file add the following to the `exe` section for the executable where you wish to have ZAbi available.

```zig
const zabi_module = b.dependency("zabi", .{}).module("zabi");
// for exe, lib, tests, etc.
exe.root_module.addImport("zabi", zabi_module);
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

### RLP Encoding and Decoding

Zabi now support RLP encoding and decoding. Bellow are examples on how to encode or decode.

#### RLP ENCODE:
```zig
const one: std.meta.Tuple(&[_]type{i8}) = .{127};
const encoded = try encodeRlp(testing.allocator, .{one});
defer testing.allocator.free(encoded);

try testing.expectEqualSlices(u8, encoded, &[_]u8{ 0xc1, 0x7f });

const multi: std.meta.Tuple(&[_]type{ i8, bool, []const u8 }) = .{ 127, false, "foobar" };
const enc_multi = try encodeRlp(testing.allocator, .{multi});
defer testing.allocator.free(enc_multi);

try testing.expectEqualSlices(u8, enc_multi, &[_]u8{ 0xc9, 0x7f, 0x80, 0x86 } ++ "foobar");

const nested: std.meta.Tuple(&[_]type{[]const u64}) = .{&[_]u64{ 69, 420 }};
const nested_enc = try encodeRlp(testing.allocator, .{nested});
defer testing.allocator.free(nested_enc);

try testing.expectEqualSlices(u8, nested_enc, &[_]u8{ 0xc5, 0xc4, 0x45, 0x82, 0x01, 0xa4 });
```

#### RLP DECODE:
```zig
const one: std.meta.Tuple(&[_]type{i8}) = .{127};
const encoded = try encodeRlp(testing.allocator, .{one});
defer testing.allocator.free(encoded);
const decoded = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{i8}), encoded);

try testing.expectEqual(one, decoded);

const multi: std.meta.Tuple(&[_]type{ i8, bool, []const u8 }) = .{ 127, false, "foobar" };
const enc_multi = try encodeRlp(testing.allocator, .{multi});
defer testing.allocator.free(enc_multi);
const decoded_multi = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{ i8, bool, []const u8 }), enc_multi);

try testing.expectEqual(multi[0], decoded_multi[0]);
try testing.expectEqual(multi[1], decoded_multi[1]);
try testing.expectEqualStrings(multi[2], decoded_multi[2]);

const nested: std.meta.Tuple(&[_]type{[]const u64}) = .{&[_]u64{ 69, 420 }};
const nested_enc = try encodeRlp(testing.allocator, .{nested});
defer testing.allocator.free(nested_enc);
const decoded_nested = try decodeRlp(testing.allocator, std.meta.Tuple(&[_]type{[]const u64}), nested_enc);
defer testing.allocator.free(decoded_nested[0]);

try testing.expectEqualSlices(u64, nested[0], decoded_nested[0]);
```

### Public Client
Zabi now commes with a http public client. It's fully capable of doing most Ethereum Json RPC request. It can also be used with a wallet instance so that you can also send transactions.

```zig
var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
defer pub_client.deinit();

const block_info = try pub_client.getBlockByHash(.{ .block_hash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
try testing.expect(block_info == .blockMerge);
try testing.expectEqual(block_info.blockMerge.number.?, 19062632);
```

### Wallet
Zabi also implements a wallet so that you can use to sign transactions/messages. It use the `libsecp256k1` C library to manage this. This is also exported via Zabi so that you can interact with it directly. With this you will gain access to the `Signer`, `Signature` and `CompactSignature` structs.

```zig
var wallet = try Wallet.init(testing.allocator, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "http://localhost:8545", .ethereum);
defer wallet.deinit();

var tx: transaction.PrepareEnvelope = .{ .eip1559 = undefined };
tx.eip1559.type = 2;
tx.eip1559.value = try utils.parseEth(1);
tx.eip1559.to = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

const tx_hash = try wallet.sendTransaction(tx);
```

These are just some of the things that zabi can do. We also have some meta programing functions for you to use as well as some other utilites functions that might be usefull for your development journey. All of this will be exposed once we have a docs website.

### Sponsors

If you find ZAbi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411). Thank you 🙏

### Contributing

Contributions to ZAbi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix.
