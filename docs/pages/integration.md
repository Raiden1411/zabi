# Integrating ZAbi

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
- zabi-clients -> contains all supported RPC clients and a block explorer clients. Also include a multicall clients as well as the wallet and contract client.
- zabi-crypto -> contains the signer used in zabi as well BIP32 and BIP39
- zabi-decoding -> contains all decoding methods supported.
- zabi-encoding -> contains all encoding methods supported.
- zabi-ens -> contains a custom ens client and utils.
- zabi-evm -> contains the EVM interpreter.
- zabi-human -> contains a custom human readable abi parser.
- zabi-meta -> contains all of the meta programming utils used in zabi.
- zabi-op-stack -> contains custom op-stack clients and utils.
- zabi-types -> contains all of the types used in zabi.
- zabi-utils -> contains all of the utils used in zabi as well as the custom cli parser data generator.
