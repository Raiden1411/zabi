const std = @import("std");
const transaction = @import("../types/transaction.zig");
const types = @import("../types/ethereum.zig");

const Address = types.Address;
const AccessList = transaction.AccessList;
const Hash = types.Hash;

pub const EVMEnviroment = struct {
    config: ConfigEnviroment,
    block: BlockEnviroment,
    tx: TxEnviroment,
};

pub const ConfigEnviroment = struct {
    chain_id: u64,
    analysed_bytecode: bool,
    limit_contract_size: ?usize,
    memory_limit: u64,
    disable_balance_check: bool,
    disable_block_gas_limit: bool,
    disable_eip3607: bool,
    disable_gas_refund: bool,
    disable_base_fee: bool,
    disable_beneficiary_reward: bool,

    pub fn default() ConfigEnviroment {
        return .{
            .chain_id = 1,
            .analysed_bytecode = false,
            .limit_contract_size = 30000,
            .memory_limit = std.math.maxInt(u32),
            .disable_eip3607 = false,
            .disable_balance_check = false,
            .disable_base_fee = false,
            .disable_beneficiary_reward = false,
            .disable_block_gas_limit = false,
            .disable_gas_refund = false,
        };
    }
};

pub const BlobExcessGasAndPrice = struct {
    blob_gasprice: u256,
    blob_excess_gas: u256,
};

pub const BlockEnviroment = struct {
    number: u256,
    coinbase: Address,
    timestamp: u256,
    gas_limit: u256,
    base_fee: u256,
    difficulty: u256,
    prevrandao: ?u256,
    blob_excess_gas_and_price: ?BlobExcessGasAndPrice,

    pub fn default() BlockEnviroment {
        return .{
            .number = 0,
            .coinbase = [_]u8{0} ** 20,
            .timestamp = 1,
            .base_fee = 0,
            .difficulty = 0,
            .prevrandao = 0,
            .blob_excess_gas_and_price = .{
                .blob_gasprice = 0,
                .blob_excess_gas = 0,
            },
        };
    }
};

pub const TxEnviroment = struct {
    caller: Address,
    gas_limit: u64,
    gas_price: u256,
    transact_to: Address,
    value: u256,
    data: []u8,
    nonce: ?u64,
    chain_id: ?u64,
    access_list: []const AccessList,
    gas_priority_fee: ?u256,
    blob_hashes: []const Hash,
    max_fee_per_blob_gas: ?u256,
    optimism: OptimismFields,
};

pub const OptimismFields = struct {
    source_hash: ?u256,
    mint: ?u128,
    is_system_tx: ?bool,
    enveloped_tx: ?[]u8,
};
