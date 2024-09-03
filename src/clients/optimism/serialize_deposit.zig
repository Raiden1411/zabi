const meta = @import("../../meta/utils.zig");
const rlp = @import("../../encoding/rlp.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("types/transaction.zig");
const types = @import("../../types/ethereum.zig");
const utils = @import("../../utils/utils.zig");

const Allocator = std.mem.Allocator;
const DepositTransaction = transaction.DepositTransaction;
const Hex = types.Hex;
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

    const encoded_sig = try rlp.encodeRlp(allocator, envelope);
    defer allocator.free(encoded_sig);

    var serialized = try allocator.alloc(u8, encoded_sig.len + 1);
    // Add the transaction type;
    serialized[0] = 0x7e;
    @memcpy(serialized[1..], encoded_sig);

    return serialized;
}
