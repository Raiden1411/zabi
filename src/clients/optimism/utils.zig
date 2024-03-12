const std = @import("std");
const testing = std.testing;
const op_transactions = @import("types/transaction.zig");
const types = @import("../../types/ethereum.zig");

const DepositData = op_transactions.DepositData;
const Hash = types.Hash;
const Hex = types.Hex;

/// This expects that the data was already decoded from hex
pub fn opaqueToDepositData(hex_bytes: Hex) !DepositData {
    comptime var position: usize = 0;

    const mint = std.mem.readInt(u256, hex_bytes[position .. position + 32], .big);
    position += 32;

    const value = std.mem.readInt(u256, hex_bytes[position .. position + 32], .big);
    position += 32;

    const gas = std.mem.readInt(u64, hex_bytes[position .. position + 8], .big);
    position += 8;

    const creation = hex_bytes[position .. position + 1][0] == 1;
    position += 1;

    const data = if (position > hex_bytes.len - 1) "0x" else hex_bytes[position..hex_bytes.len];

    return .{
        .mint = mint,
        .value = value,
        .gas = gas,
        .creation = creation,
        .data = data,
    };
}

pub fn getSourceHash() !Hash {}
