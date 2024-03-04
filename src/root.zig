pub const abi = @import("abi/abi.zig");
pub const block = @import("meta/block.zig");
pub const contract = @import("contract.zig");
pub const decoder = @import("decoding/decoder.zig");
pub const eip712 = @import("abi/eip712.zig");
pub const encoder = @import("encoding/encoder.zig");
pub const human = @import("human-readable/abi_parsing.zig");
/// Enables support for EIP-4844
pub const kzg4844 = @import("c-kzg-4844");
pub const lexer = @import("human-readable/lexer.zig");
pub const log = @import("meta/log.zig");
pub const meta = @import("meta/meta.zig");
pub const param = @import("abi/abi_parameter.zig");
pub const param_type = @import("abi/param_type.zig");
pub const parse_transacition = @import("decoding/parse_transacition.zig");
pub const rlp = @import("encoding/rlp.zig");
/// Used to manage all the signer and signatures
pub const secp256k1 = @import("secp256k1");
pub const serialize = @import("encoding/serialize.zig");
pub const state = @import("abi/state_mutability.zig");
pub const ssz = @import("encoding/ssz.zig");
pub const transactions = @import("meta/transaction.zig");
pub const tokens = @import("human-readable/tokens.zig");
pub const types = @import("meta/ethereum.zig");
pub const utils = @import("utils.zig");
pub const wallet = @import("wallet.zig");

pub const Anvil = @import("tests/Anvil.zig");
pub const Parser = @import("human-readable/Parser.zig");
pub const PubClient = @import("Client.zig");
pub const WebSocket = @import("WebSocket.zig");

test {
    const std = @import("std");
    try Anvil.waitUntilReady(std.testing.allocator, 2_000);

    _ = @import("Client.zig");
    _ = @import("WebSocket.zig");
    _ = @import("abi/param_type.zig");
    _ = @import("abi/abi_parameter.zig");
    _ = @import("abi/abi.zig");
    _ = @import("abi/state_mutability.zig");
    _ = @import("decoding/decoder.zig");
    _ = @import("decoding/parse_transacition.zig");
    _ = @import("encoding/encoder.zig");
    _ = @import("encoding/logs.zig");
    _ = @import("encoding/serialize.zig");
    _ = @import("encoding/ssz.zig");
    _ = @import("encoding/rlp.zig");
    _ = @import("human-readable/lexer.zig");
    _ = @import("human-readable/abi_parsing.zig");
    _ = @import("meta/meta.zig");
    _ = @import("utils.zig");
    // _ = @import("wallet.zig");
    // _ = @import("contract.zig");

}
