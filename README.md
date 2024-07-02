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

Zabi will support zig v0.12 and v0.13 in seperate branches. If you would like to use it you can find it in the `zig-v0.12` branch or `zig-v0.13` branch where you can build it against zig v0.12/v0.13 respectfully.
The main branch of zabi will follow the latest commits from zig and the other branch will be stable in terms of zig versions but not features from zabi.

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

    // Allocations are only made to pointer types.
    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const uri = try std.Uri.parse(parsed.url);

    var wallet: Wallet = undefined;
    try wallet.init(parsed.priv_key, .{ .allocator = gpa.allocator(), .uri = uri });
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");
    const hexed = try message.toHex(wallet.allocator);
    defer wallet.allocator.free(hexed);
    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
```

### Usage

Explore the [docs](https://zabi.sh) to find out more on how you can use or integrate Zabi in your project!

### Features

- Json RPC with support for http/s, ws/s and ipc connections.
- EVM Interperter that you can use to run contract bytecode.
- Wallet instances and contract instances to use for interacting with nodes/json rpc.
- BlockExplorer support. Only the free methods from those api endpoints are supported.
- Custom Secp256k1 ECDSA signer using only Zig and implementation of RFC6979 nonce generator.
- Custom JSON Parser that can be used to deserialize and serialized RPC data at runtime.
- ABI to zig types.
- Support for EIP712.
- Parsing of human readable ABIs into zig types with custom Parser and Lexer.
- HD Wallet and Mnemonic passphrases.
- RLP Encoding/Decoding.
- SSZ Encoding/Decoding.
- ABI Encoding/Decoding with support for Log topics encoding and decoding.
- Parsing of encoded transactions and serialization of transaction objects.
- Support for all transaction types and the new EIP4844 KZG commitments.
- Support for OPStack and ENS.
- Custom meta programming functions to transalate ABI's into zig types.
- Support for interacting with test chains such as Anvil or Hardhat.
- Custom RPC server used to fuzz data. Support http, ws and ipc.
- Custom cli args parser that translates commands to zig types and can be used to pass data to methods.
- Custom data generator usefull for fuzzing.

And a lot more yet to come...

### Goal

The goal of zabi is to be one of the best library to use by the ethereum ecosystem and to expose to more people to the zig programming language.

### Contributing

Contributions to Zabi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix.
You can also read the [contributing guide](/.github/CONTRIBUTING.md) **before submitting a pull request**

### Sponsors

If you find Zabi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411) or sending crypto to [zzabi.eth](https://etherscan.io/name-lookup-search?id=zzabi.eth) or interacting with the [drip](https://www.drips.network/app/projects/github/Raiden1411/zabi?exact) platform where 40% of the revenue gets sent to zabi's dependencies. Thank you 🙏
