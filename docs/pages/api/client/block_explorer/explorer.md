# Block Explorer

## Definition

Zabi provides a client that can be used to query block explorer like etherscan and clones of it.
Currently only free methods are provided however the paid api endpoints are also provided that you can use to build those queries if you need it.

You can use our [QueryWriter](https://github.com/Raiden1411/zabi/blob/929b2022a11e49f2a16deef7b6672524c11d4327/src/clients/url.zig#L73) to build the query strings in order to perform these requests.

You can checkout our [examples](https://github.com/Raiden1411/zabi/blob/main/examples/block_explorer/explorer.zig) to get a better idea on how to run it.

## Usage

To use the explorer client you will need the apikey and an `Allocator`. Currently in zig only TLS v1.3 is supported so any endpoint that doesnt support it you will unfortunatly get an TLS Alert error in zig. There is currently a PR in zig to add support to older TLS versions so in the future this will work by default. But as of right now only etherscan is expected to have problems with our client. For optimism and base for example this works well.

## Example

```zig
const zabi = @import("zabi");

const BlockExplorer = zabi.clients.BlockExplorer;

var explorer = BlockExplorer.init(.{
    .allocator = gpa.allocator(),
    .apikey = parsed.apikey,
});
defer explorer.deinit();

const result = try explorer.getEtherPrice();
defer result.deinit();

std.debug.print("Explorer result: {any}", .{result.response});
```
