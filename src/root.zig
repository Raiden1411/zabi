pub const abi = @import("abi.zig");
pub const block = @import("meta/block.zig");
pub const decoder = @import("decoder.zig");
pub const encoder = @import("encoder.zig");
pub const human = @import("human-readable/abi_parsing.zig");
pub const lexer = @import("human-readable/lexer.zig");
pub const log = @import("meta/log.zig");
pub const meta = @import("meta/meta.zig");
pub const param = @import("abi_parameter.zig");
pub const param_type = @import("param_type.zig");
pub const rlp = @import("rlp.zig");
pub const secp256k1 = @import("secp256k1");
pub const serialize = @import("serialize.zig");
pub const state = @import("state_mutability.zig");
pub const transactions = @import("meta/transaction.zig");
pub const tokens = @import("human-readable/tokens.zig");
pub const types = @import("meta/ethereum.zig");
pub const utils = @import("utils.zig");

pub const Anvil = @import("tests/anvil.zig").Anvil;
pub const Parser = @import("human-readable/parser.zig");
pub const PubClient = @import("client.zig");
pub const Wallet = @import("wallet.zig");

test {
    // TODO: Add this again later.
    const std = @import("std");
    var anvil: Anvil = undefined;
    try anvil.init(std.testing.allocator);
    defer anvil.deinit();
    while (true) {
        if (anvil.result.id != 0) break;
        // std.time.sleep(2 * std.time.ns_per_s);
    }

    _ = @import("param_type.zig");
    _ = @import("abi_parameter.zig");
    _ = @import("abi.zig");
    _ = @import("state_mutability.zig");
    _ = @import("human-readable/lexer.zig");
    _ = @import("human-readable/abi_parsing.zig");
    _ = @import("encoder.zig");
    _ = @import("decoder.zig");
    _ = @import("client.zig");
    _ = @import("rlp.zig");
    _ = @import("serialize.zig");
    _ = @import("client.zig");
    _ = @import("wallet.zig");
}
