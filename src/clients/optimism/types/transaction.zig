const ethereum_types = @import("../../../types/ethereum.zig");
const meta = @import("../../../meta/json.zig");

const Address = ethereum_types.Address;
const Gwei = ethereum_types.Gwei;
const Hash = ethereum_types.Hash;
const Hex = ethereum_types.Hex;
const RequestParser = meta.RequestParser;
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
