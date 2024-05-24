/// Custom cli args parser.
pub const args = @import("tests/args.zig");
/// Custom abi types into zig types.
pub const abi = @import("abi/root.zig");
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
/// Generate random data based on a provided type.
pub const generator = @import("tests/generator.zig");
/// Custom human readable parser. Supports tuples and structs.
pub const human_readable = @import("human-readable/root.zig");
/// Set of utils for meta programming in zabi as
/// well as where the custom json parser/stringify that we use resides.
pub const meta = @import("meta/root.zig");
/// KZG commitments. Related to EIP4844. Uses the c library
/// to enable support for zabi to use.
pub const kzg4844 = @import("c-kzg-4844");
/// The signatures types that zabi uses. Supports compact signatures.
pub const signature = @import("crypto/signature.zig");
/// Superchain contracts, methods and clients. Fault proofs aren't yet supported.
pub const superchain = @import("clients/optimism/root.zig");
/// Zabi's custom types for all things related to JSON RPC Requests
/// as well the currently supported chains, etc.
pub const types = @import("types/root.zig");
/// Set of nice to have utils.
pub const utils = @import("utils/utils.zig");
/// Implementation of BIP32 for Hierarchical Deterministic Wallets.
pub const hdwallet = @import("crypto/hdwallet.zig");
/// Implementation of BIP39 for mnemonic seeding and wallets.
pub const mnemonic = @import("crypto/mnemonic.zig");

/// Custom ECDSA signer that enforces signing of
/// messages with Low S since ecdsa signatures are
/// malleable and ethereum and other chains require
/// messages to be signed with low S.
pub const Signer = @import("crypto/signer.zig");
/// Custom wrapper for interacting with the Anvil testchain
pub const Anvil = @import("tests/Anvil.zig");
/// Custom wrapper for interacting with the Hardhat testchain
pub const Hardhat = @import("tests/Hardhat.zig");
/// Custom Http RPC server that server random data.
pub const RpcServer = @import("tests/clients/server.zig");
/// Custom Ws RPC server that server random data.
pub const RpcWsServerHandler = @import("tests/clients/ws_server.zig").WsHandler;
/// Used by the ws server to provide the needed context.
pub const WsServerContext = @import("tests/clients/ws_server.zig").WsContext;
/// Custom IPC RPC server that server random data.
pub const IpcRpcServer = @import("tests/clients/ipc_server.zig");

test {
    // _ = @import("abi/abi_parameter.zig");
    // _ = @import("abi/abi.zig");
    // _ = @import("abi/eip712.zig");
    // _ = @import("abi/param_type.zig");
    // _ = @import("abi/state_mutability.zig");
    // _ = @import("clients/Client.zig");
    // _ = @import("clients/WebSocket.zig");
    // _ = @import("clients/IPC.zig");
    // _ = @import("clients/contract.zig");
    // _ = @import("clients/ens/ens_utils.zig");
    // _ = @import("clients/optimism/utils.zig");
    // _ = @import("clients/optimism/parse_deposit.zig");
    // _ = @import("clients/optimism/serialize_deposit.zig");
    // _ = @import("clients/wallet.zig");
    // _ = @import("crypto/hdwallet.zig");
    // _ = @import("crypto/mnemonic.zig");
    // _ = @import("c-kzg-4844");
    // _ = @import("decoding/decoder.zig");
    // _ = @import("decoding/logs_decode.zig");
    // _ = @import("decoding/parse_transacition.zig");
    // _ = @import("decoding/rlp_decode.zig");
    // _ = @import("decoding/ssz_decode.zig");
    // _ = @import("encoding/encoder.zig");
    // _ = @import("encoding/logs.zig");
    // _ = @import("encoding/rlp.zig");
    // _ = @import("encoding/serialize.zig");
    // _ = @import("encoding/ssz.zig");
    _ = @import("evm/instructions/root.zig");
    // _ = @import("human-readable/abi_parsing.zig");
    // _ = @import("human-readable/lexer.zig");
    // _ = @import("meta/abi.zig");
    // _ = @import("meta/json.zig");
    // _ = @import("meta/utils.zig");
    // _ = @import("tests/generator.zig");
    // _ = @import("utils/utils.zig");
}
