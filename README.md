<br/>

<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Raiden1411/zabi/main/.github/zabi.svg">
      <img alt="ZAbi logo" src="https://raw.githubusercontent.com/Raiden1411/zabi/main/.github/zabi.svg" width="auto" height="150">
    </picture>
</p>

<p align="center">
  A zig library to interact with EVM blockchains 
<p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://codecov.io/github/Raiden1411/zabi/graph/badge.svg">
    <img alt="ZAbi logo" src="https://codecov.io/github/Raiden1411/zabi/graph/badge.svg" width="auto" height="25">
  </picture>
<p>

### Overview
Zabi aims to add support for interacting with ethereum or any compatible EVM based chain. 


### Zig Versions
Zabi will follow the master branch of ziglang as best as possible.


### Installing Zig
You can install the latest version of zig [here](https://ziglang.org/download/) or you can also use a version manager like [zvm](https://www.zvm.app/guides/install-zvm/) to manage your zig version.


### Integration
In the `build.zig.zon` file, add the following to the dependencies object.

```zig
.zabi = .{
    .url = "https://github.com/Raiden1411/zabi/archive/VERSION_NUMBER.tar.gz",
}
```

The compiler will produce a hash mismatch error, add the `.hash` field to `build.zig.zon`
with the hash the compiler tells you it found.
You can also use `zig fetch` to automatically do the above steps.

```bash
zig fetch --save https://github.com/Raiden1411/zabi/archive/VERSION_NUMBER.tar.gz 
zig fetch --save git+https://github.com/Raiden1411/zabi.git#LATEST_COMMIT
```

To install zabi with the latest zig version you can install it like so

```bash
zig fetch --save git+https://github.com/Raiden1411/zabi.git#zig_version_0.14.0
```

Then in your `build.zig` file add the following to the `exe` section for the executable where you wish to have `zabi` available.

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

Zabi is a modular library meaning that you can import separete modules if you just need some components of zabi.

```zig
const zabi = b.dependency("zabi", .{});
// for exe, lib, tests, etc.
exe.root_module.addImport("zabi-evm", zabi.module("zabi-evm"));
```

Now in the code, you can import components like this:

```zig
const zabi_evm = @import("zabi-evm");
```

Currently these are all of the modules available for you to use in `zabi`:
- zabi -> contains all modules.
- zabi-abi -> contains all abi types and eip712.
- zabi-ast -> contains a solidity tokenizer, parser and Ast.
- zabi-clients -> contains all supported RPC clients and a block explorer clients.
- zabi-crypto -> contains the signer used in zabi as well BIP32 and BIP39
- zabi-decoding -> contains all decoding methods supported.
- zabi-encoding -> contains all encoding methods supported.
- zabi-evm -> contains the EVM interpreter.
- zabi-human -> contains a custom human readable abi parser.
- zabi-meta -> contains all of the meta programming utils used in zabi.
- zabi-types -> contains all of the types used in zabi.
- zabi-utils -> contains all of the utils used in zabi as well as the custom cli parser data generator.


### Example Usage
You can check of the examples in the example/ folder but for a simple introduction you can checkout the bellow example.

```zig
const args_parser = @import("zabi").utils.args;
const std = @import("std");
const clients = @import("zabi").clients;

const HttpProvider = clients.Provider.HttpProvider;
const Wallet = clients.Wallet;

const CliOptions = struct {
    priv_key: [32]u8,
    url: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);
    var provider = try HttpProvider.init(.{
        .allocator = gpa.allocator(),
        .network_config = .{ .endpoint = .{ .uri = uri } },
    });
    defer provider.deinit();

    var wallet = try Wallet.init(parsed.priv_key, gpa.allocator(), &provider.provider, false);
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");

    const hexed = try message.toHex(wallet.allocator);
    defer gpa.allocator().free(hexed);

    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
```


### Features

- Json RPC with support for http/s, ws/s and ipc connections.
- EVM Interpreter that you can use to run contract bytecode.
- Wallet instances and contract instances to use for interacting with nodes/json rpc.
- Wallet nonce manager that uses a json rpc as a source of truth.
- BlockExplorer support. Only the free methods from those api endpoints are supported.
- Custom Secp256k1 ECDSA signer using only Zig and implementation of RFC6979 nonce generator.
- Custom Schnorr signer. BIP0340 and ERC-7816 are both supported.
- Custom JSON Parser that can be used to deserialize and serialized RPC data at runtime.
- Custom solidity tokenizer and parser generator.
- Ability to translate solidity source code to zig.
- ABI to zig types.
- Support for EIP712.
- Support for EIP3074 authorization message. Also supports EIP7702 transactions.
- Parsing of human readable ABIs into zig types with custom Parser and Lexer.
- HD Wallet and Mnemonic passphrases.
- RLP Encoding/Decoding.
- SSZ Encoding/Decoding.
- ABI Encoding/Decoding with support for Log topics encoding and decoding.
- Parsing of encoded transactions and serialization of transaction objects.
- Support for all transaction types and the new EIP4844 KZG commitments.
- Support for OPStack and ENS.
- Custom meta programming functions to translate ABI's into zig types.
- Support for interacting with test chains such as Anvil or Hardhat.
- Custom cli args parser that translates commands to zig types and can be used to pass data to methods.
- Custom data generator usefull for fuzzing.

And a lot more yet to come...

### Goal
The goal of zabi is to be one of the best library to use by the ethereum ecosystem and to expose to more people to the zig programming language.


### Contributing
Contributions to Zabi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix. \
You can also read the [contributing guide](/.github/CONTRIBUTING.md) **before submitting a pull request**


### Sponsors
If you find Zabi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411) or sending crypto to [zzabi.eth](https://etherscan.io/name-lookup-search?id=zzabi.eth) or interacting with the [drip](https://www.drips.network/app/projects/github/Raiden1411/zabi?exact) platform where 40% of the revenue gets sent to zabi's dependencies. Thank you 🙏
