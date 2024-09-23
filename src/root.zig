/// Custom cli args parser.
pub const args = @import("utils/args.zig");
/// Custom abi types into zig types.
pub const abi = @import("abi/root.zig");
/// Solidity tokenizer, parser and AST.
pub const ast = @import("ast/root.zig");
/// All clients that currently zabi supports and uses.
/// All data gets serialized at runtime before a request is sent.
/// The same applies for deserialization.
pub const clients = @import("clients/root.zig");
/// Set of decoding methods. Currently supported are
/// abi, logs, rlp and ssz.
pub const decoding = @import("decoding/root.zig");
/// Set of encoding methods. Currently supported are
/// abi, logs, rlp and ssz.
pub const encoding = @import("encoding/root.zig");
/// Currently minimal support for interacting with ens resolvers
/// More functionality will be added in the future.
pub const ens = @import("clients/ens/root.zig");
/// Similar to tools like "dotenv". Used internally by our tests
/// to load the necessary anvil variables from `.env` file.
pub const env_load = @import("utils/env_load.zig");
/// Evm implementation. For now it contains the interpreter and other needed instances
/// like `Contract`, `Host` and `EVMEnviroment` among other things.
pub const evm = @import("evm/root.zig");
/// Generate random data based on a provided type.
pub const generator = @import("utils/generator.zig");
/// Implementation of BIP32 for Hierarchical Deterministic Wallets.
pub const hdwallet = @import("crypto/hdwallet.zig");
/// Custom human readable parser. Supports tuples and structs.
pub const human_readable = @import("human-readable/root.zig");
/// KZG commitments. Related to EIP4844. Uses the c library
/// to enable support for zabi to use.
pub const kzg4844 = @import("c-kzg-4844");
/// Set of utils for meta programming in zabi as
/// well as where the custom json parser/stringify that we use resides.
pub const meta = @import("meta/root.zig");
/// Implementation of BIP39 for mnemonic seeding and wallets.
pub const mnemonic = @import("crypto/mnemonic.zig");
/// Multicall contract wrapper that exposes contract functions.
pub const multicall = @import("clients/multicall.zig");
/// Network config for different type of chains and associated contracts.
pub const network = @import("clients/network.zig");
/// The signatures types that zabi uses. Supports compact signatures.
pub const signature = @import("crypto/signature.zig");
/// Superchain contracts, methods and clients. Fault proofs aren't yet supported.
pub const superchain = @import("clients/optimism/root.zig");
/// Zabi's custom types for all things related to JSON RPC Requests
/// as well the currently supported chains, etc.
pub const types = @import("types/root.zig");
/// Dedicated `searchUrlParams` for zabi expected types.
/// This also includes the `QueryWriter` which details the supported types
pub const url = @import("clients/url.zig");
/// Set of nice to have utils.
pub const utils = @import("utils/utils.zig");

/// Custom wrapper for interacting with the Anvil testchain
pub const Anvil = @import("clients/Anvil.zig");
/// Custom wrapper for interacting with the Hardhat testchain
pub const Hardhat = @import("clients/Hardhat.zig");
/// Custom IPC RPC server that server random data.
pub const IpcRpcServer = @import("server/ipc_server.zig");
/// Custom Http RPC server that server random data.
pub const RpcServer = @import("server/server.zig");
/// Custom Ws RPC server that server random data.
pub const RpcWsServerHandler = @import("server/ws_server.zig").WsHandler;
/// Custom ECDSA signer that enforces signing of
/// messages with Low S since ecdsa signatures are
/// malleable and ethereum and other chains require
/// messages to be signed with low S.
pub const Signer = @import("crypto/Signer.zig");
/// Used by the ws server to provide the needed context.
pub const WsServerContext = @import("server/ws_server.zig").WsContext;

test {
    _ = @import("tests/root.zig");
}
