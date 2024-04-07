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

### Overview
Zabi aims to add support for interacting with ethereum and EVM based chains. By default it comes with almost all of the features you would expect from an ethereum library. From RLP encoding/decoding, to wallet and contract instances, to a http or a websocket client and much more.

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

    const parsed = args_parser.parseArgs(CliOptions, &iter);

    const uri = try std.Uri.parse(parsed.url);

    var wallet: Wallet = undefined;
    try wallet.init(parsed.priv_key, .{ .allocator = gpa.allocator(), .uri = uri });
    defer wallet.deinit();

    const message = try wallet.signEthereumMessage("Hello World");
    const hexed = try message.toHex(wallet.allocator);
    defer gpa.allocator().free(hexed);
    std.debug.print("Ethereum message: {s}\n", .{hexed});
}
```

### Usage

Explore the [docs](https://zabi.sh) to find out more on how you can use or integrate Zabi in your project!

### Sponsors

If you find Zabi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411) or sending crypto to [zzabi.eth](https://etherscan.io/name-lookup-search?id=zzabi.eth) or interacting with the [drip](https://www.drips.network/app/projects/github/Raiden1411/zabi?exact) platform where 40% of the revenue gets sent to zabi's dependencies. Thank you 🙏

### Contributing

Contributions to Zabi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix.
