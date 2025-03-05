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

Zabi will support zig v0.14 in separate branches. If you would like to use it you can find it in the `zig_version_0.14.0` branch where you can build it against zig 0.13.0.
The main branch of zabi will follow the latest commits from zig and the other branch will be stable in terms of zig versions but not features from zabi.

### Integration
You can check how to integrate ZABI in your project [here](https://www.zabi.sh/integration)

### Example Usage
```zig
const args_parser = zabi.args;
const std = @import("std");
const zabi = @import("zabi");
const Wallet = zabi.clients.wallet.Wallet(.http);

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

    var wallet = try Wallet.init(parsed.priv_key, .{
        .allocator = gpa.allocator(),
        .network_config = .{ .endpoint = .{ .uri = uri } },
    }, false);
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");

    const hexed = try message.toHex(wallet.allocator);
    defer gpa.allocator().free(hexed);

    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
```

### Usage

Explore the [docs](https://zabi.sh) to find out more on how you can use or integrate Zabi in your project!

### Installing Zig

You can install the latest version of zig [here](https://ziglang.org/download/) or you can also use a version manager like [zvm](https://www.zvm.app/guides/install-zvm/) to manage your zig version.

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
