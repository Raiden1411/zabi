pub const abi = @import("abi/abi.zig");
pub const block = @import("meta/block.zig");
pub const contract = @import("clients/contract.zig");
pub const decoder = @import("decoding/decoder.zig");
pub const decoder_logs = @import("decoding/logs_decode.zig");
pub const eip712 = @import("abi/eip712.zig");
pub const encoder = @import("encoding/encoder.zig");
pub const encoder_logs = @import("encoding/logs.zig");
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
pub const rlp_decode = @import("decoding/rlp_decode.zig");
/// Used to manage all the signer and signatures
pub const secp256k1 = @import("secp256k1");
pub const serialize = @import("encoding/serialize.zig");
pub const state_mutability = @import("abi/state_mutability.zig");
pub const ssz = @import("encoding/ssz.zig");
pub const ssz_decode = @import("decoding/ssz_decode.zig");
pub const transactions = @import("meta/transaction.zig");
pub const tokens = @import("human-readable/tokens.zig");
pub const types = @import("meta/ethereum.zig");
pub const utils = @import("utils/utils.zig");
pub const wallet = @import("clients/wallet.zig");

pub const Anvil = @import("tests/Anvil.zig");
pub const Parser = @import("human-readable/Parser.zig");
pub const PubClient = @import("clients/Client.zig");
pub const WebSocket = @import("clients/WebSocket.zig");

test {
    const std = @import("std");
    try Anvil.waitUntilReady(std.testing.allocator, 2_000);

    _ = @import("abi/param_type.zig");
    _ = @import("abi/abi_parameter.zig");
    _ = @import("abi/abi.zig");
    _ = @import("abi/state_mutability.zig");
    _ = @import("decoding/decoder.zig");
    _ = @import("decoding/logs_decode.zig");
    _ = @import("decoding/parse_transacition.zig");
    _ = @import("decoding/rlp_decode.zig");
    _ = @import("decoding/ssz_decode.zig");
    _ = @import("clients/Client.zig");
    _ = @import("clients/WebSocket.zig");
    _ = @import("clients/contract.zig");
    _ = @import("clients/wallet.zig");
    _ = @import("encoding/encoder.zig");
    _ = @import("encoding/logs.zig");
    _ = @import("encoding/rlp.zig");
    _ = @import("encoding/serialize.zig");
    _ = @import("encoding/ssz.zig");
    _ = @import("human-readable/abi_parsing.zig");
    _ = @import("human-readable/lexer.zig");
    _ = @import("meta/meta.zig");
    _ = @import("utils/utils.zig");
}
