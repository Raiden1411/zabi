const ethereum_types = @import("../../../types/ethereum.zig");
const meta = @import("../../../meta/json.zig");
const transaction_types = @import("../../../types/transaction.zig");

const Address = ethereum_types.Address;
const Gwei = ethereum_types.Gwei;
const Hash = ethereum_types.Hash;
const Hex = ethereum_types.Hex;
const RequestParser = meta.RequestParser;
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
    isSystemTx: bool,
    depositReceiptVersion: ?u64 = null,

    pub usingnamespace RequestParser(@This());
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
