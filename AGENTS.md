# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Commands

- **Build:** `zig build`
- **Build Examples:** `zig build examples`
- **Build Benchmark:** `zig build bench`
- **Build Coverage:** `zig build coverage`
- **Build Benchmark Fast:** `zig build bench -Doptimize=ReleaseFast`
- **Test (Zig):** `zig build test -freference-trace=256 -Dload_variables`
- **Test CI (Zig):** `zig build test-ci -freference-trace=256 -Dload_variables`
- **Test Module (Zig)**: `zig build test -Dtest-filter="<module name>" -freference-trace=256 -Dload_variables`
- **Formatting (Zig)**: `zig fmt .`

### Notes
For testing the use of `-Dload_variables` loads the `.env` file present in the root. This depends on `anvil` being run in another process.
For coverage and benchmark the testing this is ran `tests/root_benchmark.zig` and excludes rpc client tests. Doesnt depend on `anvil`
For test filters this will only work if specifing the module names. To find them please go to `./src/root.zig`. To check specific tests inside of those modules use grep or rg.

## Directory Structure

- Zig core: `src/`
- Testing core: `tests/`
- Builtin packages: `pkg/`
- Example code: `examples/`
- Build code dependencies: `build/`

## Core structure

- `src/abi` has all solidity abi types and custom logic to handle json parsing. Also include dedicated methods for encoding and decoding
- `src/types` has all types that are shared in zabi with custom json parsing.
- `src/decoding` handles of the decoding operations for ABI types and ABI Log types. Also handle decoding of transactions
- `src/encoding` handles of the encoding operations for ABI types and ABI Log types. Also handles encoding of transactions
- `src/crypto` custom signer implementation to make sending ethereum transactions possible. Also handles mnemonics and HDWallets.
- `src/ast` parses solidity source code and builds and ast for it. Also has custom formatting builtin for it.
- `src/evm` custom evm interpreter with state handing logic.
- `src/human-readable` custom parser to convert human-readable solidity definitions to abi types.
- `src/clients` RPC clients that support Websocket, IPC and HTTP/S connections. Provides a general interface in `./src/clients/Provider.zig` that is used by all clients. Also has dedicated helpers for opchain and ens contracts.
- `src/wasm` set of wasm compilable functions
- `src/meta` custom implementation of json parsing to support hex encoded strings and also some compile time type generation.

## Testing stratagy
- Unit tests in each module
- Example projects that demonstrate module usage
- Benchmark if needed when core logic is updated
- Prefer the use of `zig build test -Dtest-filter="<module name>" -freference-trace=256 -Dload_variables` if not testing any RPC clients.
- When running RPC client tests **ASK** user if anvil dependency is running

When adding new features:
- Include tests for new functionality
- Update relevant examples if needed
