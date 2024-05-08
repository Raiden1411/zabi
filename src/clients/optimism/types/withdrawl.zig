const types = @import("../../../types/ethereum.zig");
const utils = @import("../../../meta/utils.zig");

const Address = types.Address;
const Gwei = types.Gwei;
const Hash = types.Hash;
const Hex = types.Hex;
const MergeStructs = utils.MergeStructs;
const Omit = utils.Omit;
const Wei = types.Wei;

pub const Message = struct {
    blockNumber: u64,
    messages: []const Withdrawal,
};

pub const WithdrawalRequest = struct {
    data: ?Hex = null,
    gas: ?Gwei = null,
    to: Address,
    value: ?Wei = null,
};

pub const PreparedWithdrawal = struct {
    data: Hex,
    gas: Gwei,
    to: Address,
    value: Wei,
};

pub const Withdrawal = struct {
    nonce: Wei,
    sender: Address,
    target: Address,
    value: Wei,
    gasLimit: Wei,
    data: Hex,
    withdrawalHash: Hash,
};

pub const WithdrawalNoHash = Omit(Withdrawal, &.{"withdrawalHash"});

pub const WithdrawalRootProof = struct {
    version: Hash,
    stateRoot: Hash,
    messagePasserStorageRoot: Hash,
    latestBlockhash: Hash,
};

pub const Proofs = struct {
    outputRootProof: WithdrawalRootProof,
    withdrawalProof: []const Hex,
    l2OutputIndex: u256,
};

pub const WithdrawalEnvelope = MergeStructs(WithdrawalNoHash, Proofs);

pub const ProvenWithdrawal = struct {
    outputRoot: Hash,
    timestamp: u128,
    l2OutputIndex: u128,
};

pub const Game = struct {
    index: u256,
    metadata: Hash,
    timestamp: u64,
    rootClaim: Hash,
    extraData: Hex,
};

pub const GameResult = struct {
    index: u256,
    metadata: Hash,
    timestamp: u64,
    rootClaim: Hash,
    l2BlockNumber: u256,
};
