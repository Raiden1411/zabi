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
    messages: []const Withdrawl,
};

pub const Withdrawl = struct {
    nonce: Wei,
    sender: Address,
    target: Address,
    value: Wei,
    gasLimit: Wei,
    data: Hex,
    withdrawalHash: Hash,
};

pub const WithdrawlNoHash = Omit(Withdrawl, &.{"withdrawalHash"});

pub const WithdrawlRootProof = struct {
    version: Hash,
    stateRoot: Hash,
    messagePasserStorageRoot: Hash,
    latestBlockhash: Hash,
};

pub const Proofs = struct {
    outputRootProof: WithdrawlRootProof,
    withdrawalProof: []const Hex,
    l2OutputIndex: u256,
};

pub const WithdrawlEnvelope = MergeStructs(WithdrawlNoHash, Proofs);
