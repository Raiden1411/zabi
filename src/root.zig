pub const abi = @import("abi/root.zig");
pub const clients = @import("clients/root.zig");
pub const decoding = @import("decoding/root.zig");
pub const encoding = @import("encoding/root.zig");
pub const human_readable = @import("human-readable/root.zig");
pub const meta = @import("meta/root.zig");
pub const kzg4844 = @import("c-kzg-4844");
pub const signature = @import("crypto/signature.zig");
pub const superchain = @import("clients/optimism/root.zig");
pub const types = @import("types/root.zig");
pub const utils = @import("utils/utils.zig");
pub const hdwallet = @import("crypto/hdwallet.zig");
pub const mnemonic = @import("crypto/mnemonic.zig");

pub const Signer = @import("crypto/signer.zig");
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
    _ = @import("clients/WebSocket.zig");
    _ = @import("clients/contract.zig");
    _ = @import("clients/wallet.zig");
    _ = @import("clients/optimism/clients/L1PubClient.zig");
    _ = @import("clients/optimism/clients/L1WalletClient.zig");
    _ = @import("clients/optimism/clients/L2PubClient.zig");
    _ = @import("clients/optimism/clients/L2WalletClient.zig");
    _ = @import("clients/optimism/utils.zig");
    _ = @import("clients/optimism/parse_deposit.zig");
    _ = @import("clients/optimism/serialize_deposit.zig");
    _ = @import("crypto/hdwallet.zig");
    _ = @import("crypto/mnemonic.zig");
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
