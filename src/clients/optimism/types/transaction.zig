const std = @import("std");
const ethereum_types = @import("../../../types/ethereum.zig");
const meta = @import("../../../meta/root.zig");
const transaction_types = @import("../../../types/transaction.zig");

const Allocator = std.mem.Allocator;
const Address = ethereum_types.Address;
const Gwei = ethereum_types.Gwei;
const Hash = ethereum_types.Hash;
const Hex = ethereum_types.Hex;
const ParseError = std.json.ParseError;
const ParseFromValueError = std.json.ParseFromValueError;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;
const TransactionTypes = transaction_types.TransactionTypes;
const Wei = ethereum_types.Wei;

pub const DepositTransaction = struct {
    sourceHash: Hash,
    from: Address,
    to: ?Address,
    mint: u256,
    value: Wei,
    gas: Gwei,
    isSystemTx: bool,
    data: ?Hex,
};

pub const DepositTransactionSigned = struct {
    hash: Hash,
    nonce: u64,
    blockHash: ?Hash,
    blockNumber: ?u64,
    transactionIndex: ?u64,
    from: Address,
    to: ?Address,
    value: Wei,
    gasPrice: Gwei,
    gas: Gwei,
    input: Hex,
    v: usize,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    r: u256,
    /// Represented as values instead of the hash because
    /// a valid signature is not guaranteed to be 32 bits
    s: u256,
    type: TransactionTypes,
    sourceHash: Hex,
    mint: ?u256 = null,
    isSystemTx: ?bool = null,
    depositReceiptVersion: ?u64 = null,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) ParseError(@TypeOf(source.*))!@This() {
        return meta.json.jsonParse(@This(), allocator, source, options);
    }

    pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) ParseFromValueError!@This() {
        return meta.json.jsonParseFromValue(@This(), allocator, source, options);
    }

    pub fn jsonStringify(self: @This(), writer_stream: anytype) @TypeOf(writer_stream.*).Error!void {
        return meta.json.jsonStringify(@This(), self, writer_stream);
    }
};

pub const DepositData = struct {
    mint: u256,
    value: Wei,
    gas: Gwei,
    creation: bool,
    data: ?Hex,
};

pub const TransactionDeposited = struct {
    from: Address,
    to: Address,
    version: u256,
    opaqueData: Hex,
    logIndex: usize,
    blockHash: Hash,
};

pub const DepositTransactionEnvelope = struct {
    gas: ?Gwei = null,
    mint: ?Wei = null,
    value: ?Wei = null,
    creation: bool = false,
    data: ?Hex = null,
    to: ?Address = null,
};
