const meta = @import("zabi-meta").utils;
const std = @import("std");
const testing = std.testing;
const transaction = @import("zabi-types").transactions;
const types = @import("zabi-types").ethereum;
const utils = @import("zabi-utils").utils;

const Allocator = std.mem.Allocator;
const DepositTransaction = transaction.DepositTransaction;
const Hex = types.Hex;
const RlpEncoder = @import("zabi-encoding").RlpEncoder;
const StructToTupleType = meta.StructToTupleType;

/// Serializes an OP deposit transaction
/// Caller owns the memory
pub fn serializeDepositTransaction(allocator: Allocator, tx: DepositTransaction) ![]u8 {
    const envelope: StructToTupleType(DepositTransaction) = .{
        tx.sourceHash,
        tx.from,
        tx.to,
        tx.mint,
        tx.value,
        tx.gas,
        tx.isSystemTx,
        tx.data,
    };

    const encoded_sig = try RlpEncoder.encodeRlp(allocator, envelope);
    defer allocator.free(encoded_sig);

    var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
    // Add the transaction type;
    serialized[0] = 0x7e;
    @memcpy(serialized[1..], encoded_sig);

    return serialized;
}
