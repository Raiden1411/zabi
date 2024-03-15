pub const abi = @import("abi/root.zig");
pub const clients = @import("clients/root.zig");
pub const decoding = @import("decoding/root.zig");
pub const encoding = @import("encoding/root.zig");
pub const human_readable = @import("human-readable/root.zig");
pub const meta = @import("meta/root.zig");
pub const kzg4844 = @import("c-kzg-4844");
pub const signer = @import("secp256k1");
pub const types = @import("types/root.zig");
pub const utils = @import("utils/utils.zig");

pub const Anvil = @import("tests/Anvil.zig");
pub const Hardhat = @import("tests/Hardhat.zig");

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
    // _ = @import("clients/WebSocket.zig");
    // _ = @import("clients/contract.zig");
    // _ = @import("clients/wallet.zig");
    // _ = @import("clients/optimism/clients/Optimism.zig");
    // _ = @import("clients/optimism/clients/OptimismL1.zig");
    // _ = @import("clients/optimism/clients/WalletOptimism.zig");
    // _ = @import("clients/optimism/clients/WalletOptimismL1.zig");
    _ = @import("clients/optimism/parse_deposit.zig");
    _ = @import("clients/optimism/serialize_deposit.zig");
    _ = @import("encoding/encoder.zig");
    _ = @import("encoding/logs.zig");
    _ = @import("encoding/rlp.zig");
    _ = @import("encoding/serialize.zig");
    _ = @import("encoding/ssz.zig");
    _ = @import("human-readable/abi_parsing.zig");
    _ = @import("human-readable/lexer.zig");
    _ = @import("meta/abi.zig");
    _ = @import("meta/utils.zig");
    _ = @import("utils/utils.zig");
}
