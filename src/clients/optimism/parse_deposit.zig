const meta = @import("../../meta/utils.zig");
const rlp = @import("../../decoding/rlp_decode.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("types/transaction.zig");
const utils = @import("../../utils/utils.zig");

const serializeDepositTransaction = @import("serialize_deposit.zig").serializeDepositTransaction;

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
