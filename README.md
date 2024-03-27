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
Zabi aims to add support for interacting with ethereum and EVM based chains. By default it comes with almost all of the features you would expect from a ethereum library. From RLP encoding/decoding, to wallet and contract instances, to a http or a websocket client and much more.

```zig
const std = @import("std");
const zabi = @import("zabi");
const Wallet = zabi.wallet.Wallet(.http);
 
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var iter = try std.process.ArgIterator.initWithAllocator(gpa.allocator());
    defer iter.deinit();
 
    _ = iter.skip();
 
    const priv_key = iter.next().?
    const host_url = iter.next().?

    const uri = try std.Uri.parse(host_url);
    var bytes_priv_key: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes_priv_key, priv_key);
 
    // The chain defaults to ethereum if it's not specified.
    var wallet: Wallet = undefined;
    try wallet.init(bytes_priv_key, .{.allocator = gpa.allocator(), .uri = uri });
    defer wallet.deinit();
 
    const message = try wallet.signEthereumMessage("Hello World");

    const hex_sig = try message.toHex(wallet.allocator);
    defer wallet.allocator.free(hex_sig);

    std.debug.print("Ethereum message: 0x{s}\n", .{hex_sig});
}
```

### Usage

Explore the [docs](https://zabi.sh) to find out more on how you can use or integrate Zabi in your project!

### Sponsors

If you find Zabi useful or use it for work, please consider supporting development on [GitHub Sponsors]( https://github.com/sponsors/Raiden1411) or sending crypto to [zzabi.eth](https://etherscan.io/name-lookup-search?id=zzabi.eth) or interacting with the [drip](https://www.drips.network/app/projects/github/Raiden1411/zabi?exact) platform where 40% of the revenue gets sent to zabi's dependencies. Thank you 🙏

### Contributing

Contributions to Zabi are greatly appreciated! If you're interested in contributing to ZAbi, feel free to create a pull request with a feature or a bug fix.
