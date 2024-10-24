const meta = @import("zabi-meta").utils;
const rlp = @import("zabi-decoding").rlp;
const std = @import("std");
const testing = std.testing;
const transaction = @import("zabi-types").transactions;
const utils = @import("zabi-utils").utils;

const Allocator = std.mem.Allocator;
const DepositTransaction = transaction.DepositTransaction;
const StructToTupleType = meta.StructToTupleType;

/// Parses a deposit transaction into its zig type
/// Only the data field will have allocated memory so you must free it after
pub fn parseDepositTransaction(allocator: Allocator, encoded: []u8) !DepositTransaction {
    if (encoded[0] != 0x7e)
        return error.InvalidTransactionType;

    // zig fmt: off
    const source_hash,
    const from,
    const to,
    const mint, 
    const value, 
    const gas, 
    const is_system,
    const data = try rlp.decodeRlp(allocator, StructToTupleType(DepositTransaction), encoded[1..]);
    // zig fmt: on

    return .{
        .sourceHash = source_hash,
        .isSystemTx = is_system,
        .gas = gas,
        .from = from,
        .to = to,
        .value = value,
        .data = data,
        .mint = mint,
    };
}
