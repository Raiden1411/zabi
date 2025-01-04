const constants = @import("zabi-utils").constants;
const specification = @import("specification.zig");
const std = @import("std");
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_types = @import("zabi-types");

const Address = types.Address;
const AccessList = transaction.AccessList;
const Hash = types.Hash;
const SpecId = specification.SpecId;

/// Set of validation errors from a `EVMEnviroment`.
pub const ValidationErrors = error{
    PriorityFeeGreaterThanMaxFee,
    GasPriceLessThanBaseFee,
    GasLimitHigherThanBlock,
    TooManyBlobs,
    BlobCreateTransaction,
    BlobVersionNotSupported,
    BlobVersionedHashesNotSupported,
    BlobGasPriceHigherThanMax,
    EmptyBlobs,
    InvalidChainId,
    AccessListNotSupported,
};

/// The EVM inner enviroment.
pub const EVMEnviroment = struct {
    /// Configuration of the EVM.
    config: ConfigEnviroment,
    /// Configuration of the block the transaction is in.
    block: BlockEnviroment,
    /// Configuration of the transaction that is being executed.
    tx: TxEnviroment,

    /// Creates a default EVM enviroment.
    pub fn default() EVMEnviroment {
        return .{
            .config = ConfigEnviroment.default(),
            .block = BlockEnviroment.default(),
            .tx = TxEnviroment.default(),
        };
    }
    /// Calculates the effective gas price of the transaction.
    pub fn effectiveGasPrice(self: EVMEnviroment) u256 {
        if (self.tx.gas_priority_fee) |fee| {
            return @min(self.tx.gas_price, self.block.base_fee + fee);
        } else return self.tx.gas_price;
    }
    /// Calculates the `data_fee` of the transaction.
    /// This will return null if cancun is not enabled.
    ///
    /// See EIP-4844:
    /// <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>
    pub fn calculateDataFee(self: EVMEnviroment) ?u256 {
        if (self.block.blob_excess_gas_and_price) |fees| {
            return fees.blob_gasprice * self.tx.getTotalBlobGas();
        } else return null;
    }
    /// Calculates the max `data_fee` of the transaction.
    /// This will return null if cancun is not enabled.
    ///
    /// See EIP-4844:
    /// <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>
    pub fn calculateMaxDataFee(self: EVMEnviroment) ?u256 {
        if (self.tx.max_fee_per_blob_gas) |fee| {
            return @truncate(fee * self.tx.getTotalBlobGas());
        } else return null;
    }
    /// Validates the inner block enviroment based on the provided `SpecId`
    pub fn validateBlockEnviroment(
        self: EVMEnviroment,
        spec: SpecId,
    ) error{ PrevRandaoNotSet, ExcessBlobGasNotSet }!void {
        if (spec.enabled(.MERGE) and self.block.prevrandao == null)
            return error.PrevRandaoNotSet;

        if (spec.enabled(.CANCUN) and self.block.blob_excess_gas_and_price == null)
            return error.ExcessBlobGasNotSet;
    }
    /// Validates the transaction enviroment.
    /// For `CANCUN` enabled and later checks the gas price is not more than the transactions max
    /// and checks if the blob_hashes are correctly set.
    ///
    /// For before `CANCUN` checks if `blob_hashes` and `max_fee_per_blob_gas` are null / empty.
    pub fn validateTransaction(
        self: EVMEnviroment,
        spec: SpecId,
    ) ValidationErrors!void {
        if (spec.enabled(.LONDON)) {
            if (self.tx.gas_priority_fee) |fee| {
                if (fee > self.tx.gas_price)
                    return error.PriorityFeeGreaterThanMaxFee;
            }

            if (!self.config.disable_base_fee and self.effectiveGasPrice() < self.block.base_fee)
                return error.GasPriceLessThanBaseFee;
        }

        if (!self.config.disable_block_gas_limit and self.tx.gas_limit > self.block.gas_limit)
            return error.GasLimitHigherThanBlock;

        if (self.tx.chain_id) |chain_id| {
            if (chain_id != self.config.chain_id)
                return error.InvalidChainId;
        }

        if (!spec.enabled(.BERLIN) and self.tx.access_list.len != 0) {
            return error.AccessListNotSupported;
        }

        if (spec.enabled(.CANCUN)) {
            if (self.tx.max_fee_per_blob_gas) |max| {
                const price = self.block.blob_excess_gas_and_price orelse return error.ExpectedBlobPrice;

                if (price.blob_gasprice > max)
                    return error.BlobGasPriceHigherThanMax;
            }

            if (self.tx.blob_hashes.len == 0)
                return error.EmptyBlobs;

            if (self.tx.transact_to == .create)
                return error.BlobCreateTransaction;

            for (self.tx.blob_hashes) |hashes| {
                if (hashes[0] != constants.VERSIONED_HASH_VERSION_KZG)
                    return error.BlobVersionNotSupported;
            }

            if (self.tx.blob_hashes.len > constants.MAX_BLOB_NUMBER_PER_BLOCK)
                return error.TooManyBlobs;
        } else {
            if (self.tx.blob_hashes.len != 0)
                return error.BlobVersionedHashesNotSupported;

            if (self.tx.max_fee_per_blob_gas != null)
                return error.MaxFeePerBlobGasNotSupported;
        }
    }
    // TODO: Validate against State.
};

/// The EVM Configuration enviroment.
pub const ConfigEnviroment = struct {
    /// The chain id of the EVM. It will be compared with the `tx` chain id.
    chain_id: u64,
    /// Whether to perform analysis on the bytecode.
    perform_analysis: AnalysisKind,
    /// The contract code's size limit.
    ///
    /// By default if should be 24kb as part of the Spurious Dragon upgrade via [EIP-155].
    ///
    /// [EIP-155]: https://eips.ethereum.org/EIPS/eip-155
    limit_contract_size: ?usize,
    /// The max size that the memory can grow too with failing with `OutOfGas` errors.
    memory_limit: u64,
    /// Skips balance checks if enabled. Adds transaction cost to ensure execution doesn't fail.
    disable_balance_check: bool,
    /// There are use cases where it's allowed to provide a gas limit that's higher than a block's gas limit.
    /// To that end, you can disable the block gas limit validation.
    disable_block_gas_limit: bool,
    /// EIP-3607 rejects transactions from senders with deployed code. In development, it can be desirable to simulate
    /// calls from contracts, which this setting allows.
    disable_eip3607: bool,
    /// Disables all gas refunds. This is useful when using chains that have gas refunds disabled e.g. Avalanche.
    /// Reasoning behind removing gas refunds can be found in EIP-3298.
    disable_gas_refund: bool,
    /// Disables base fee checks for EIP-1559 transactions.
    /// This is useful for testing method calls with zero gas price.
    disable_base_fee: bool,
    /// Disables the payout of the reward to the beneficiary.
    disable_beneficiary_reward: bool,

    /// Returns the set of default values for a `ConfigEnviroment`.
    pub fn default() ConfigEnviroment {
        return .{
            .chain_id = 1,
            .perform_analysis = .analyse,
            .limit_contract_size = 0x600,
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

/// Type that representes the excess blob gas and it's price.
pub const BlobExcessGasAndPrice = struct {
    blob_gasprice: u256,
    blob_excess_gas: u256,

    /// Calculates the price based on the provided `excess_gas`.
    pub fn init(excess_gas: u64) BlobExcessGasAndPrice {
        const price = utils.calcultateBlobGasPrice(excess_gas);

        return .{
            .blob_gasprice = price,
            .blob_excess_gas = excess_gas,
        };
    }
};

/// The block enviroment.
pub const BlockEnviroment = struct {
    /// The number of previous blocks of this block (block height).
    number: u256,
    /// Coinbase or miner or address that created and signed the block.
    ///
    /// This is the receiver address of all the gas spent in the block.
    coinbase: Address,
    /// The timestamp of the block in seconds since the UNIX epoch.
    timestamp: u256,
    /// The gas limit of the block.
    gas_limit: u256,
    /// The base fee per gas, added in the London upgrade with [EIP-1559].
    ///
    /// [EIP-1559]: https://eips.ethereum.org/EIPS/eip-1559
    base_fee: u256,
    /// The difficulty of the block.
    ///
    /// Unused after the Paris (AKA the merge) upgrade, and replaced by `prevrandao`.
    difficulty: u256,
    /// The output of the randomness beacon provided by the beacon chain.
    ///
    /// Replaces `difficulty` after the Paris (AKA the merge) upgrade with [EIP-4399].
    ///
    /// NOTE: `prevrandao` can be found in a block in place of `mix_hash`.
    ///
    /// [EIP-4399]: https://eips.ethereum.org/EIPS/eip-4399
    prevrandao: ?u256,
    /// Excess blob gas and blob gasprice. Check `BlobExcessGasAndPrice`
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    blob_excess_gas_and_price: ?BlobExcessGasAndPrice,

    /// Returns a set of default values for this `BlockEnviroment`.
    pub fn default() BlockEnviroment {
        return .{
            .number = 0,
            .coinbase = [_]u8{0} ** 20,
            .timestamp = 1,
            .base_fee = 0,
            .difficulty = 0,
            .prevrandao = 0,
            .gas_limit = 0,
            .blob_excess_gas_and_price = .{
                .blob_gasprice = 0,
                .blob_excess_gas = 0,
            },
        };
    }
};

/// The transaction enviroment.
pub const TxEnviroment = struct {
    /// The signer of this transaction.
    caller: Address,
    /// The gas limit for this transaction.
    gas_limit: u64,
    /// The gas price for this transaction.
    gas_price: u256,
    /// The target of this transaction.
    transact_to: AddressKind,
    /// The value sent in this transaction.
    value: u256,
    /// The data of the transaction.
    data: []u8,
    /// The nonce of this transaction.
    ///
    /// Caution: If set to `null`, then nonce validation against the account's nonce is skipped.
    nonce: ?u64,
    /// The chain ID of the transaction. If set to `null`, no checks are performed.
    ///
    /// Incorporated as part of the Spurious Dragon upgrade via [EIP-155].
    ///
    /// [EIP-155]: https://eips.ethereum.org/EIPS/eip-155
    chain_id: ?u64,
    /// A list of addresses and storage keys that the transaction plans to access.
    ///
    /// Added in [EIP-2930].
    ///
    /// [EIP-2930]: https://eips.ethereum.org/EIPS/eip-2930
    access_list: []const AccessList,
    /// The priority fee per gas.
    ///
    /// Incorporated as part of the London upgrade via [EIP-1559].
    ///
    /// [EIP-1559]: https://eips.ethereum.org/EIPS/eip-1559
    gas_priority_fee: ?u256,
    /// The list of blob versioned hashes. Per EIP there should be at least
    /// one blob present if `max_fee_per_blob_gas` isn't null.
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    blob_hashes: []const Hash,
    /// The max fee per blob gas.
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    max_fee_per_blob_gas: ?u256,
    /// `Optimism` dedicated fields.
    optimism: OptimismFields,

    /// Returns a default `TxEnviroment`.
    pub fn default() TxEnviroment {
        return .{
            .caller = [_]u8{0} ** 20,
            .gas_limit = 0,
            .gas_price = 0,
            .transact_to = .{ .call = [_]u8{1} ** 20 },
            .value = 0,
            .data = &.{},
            .nonce = 0,
            .chain_id = 1,
            .access_list = &.{},
            .gas_priority_fee = 0,
            .blob_hashes = &.{},
            .max_fee_per_blob_gas = 0,
            .optimism = OptimismFields.default(),
        };
    }
    /// Gets the total blob gas in this `TxEnviroment`.
    pub fn getTotalBlobGas(self: TxEnviroment) u64 {
        return @intCast(constants.GAS_PER_BLOB * self.blob_hashes.len);
    }
};

/// Set of `Optimism` fields for the transaction enviroment.
pub const OptimismFields = struct {
    /// The source hash is used to make sure that deposit transactions do
    /// not have identical hashes.
    ///
    /// L1 originated deposit transaction source hashes are computed using
    /// the hash of the l1 block hash and the l1 log index.
    /// L1 attributes deposit source hashes are computed with the l1 block
    /// hash and the sequence number = l2 block number - l2 epoch start
    /// block number.
    ///
    /// These two deposit transaction sources specify a domain in the outer
    /// hash so there are no collisions.
    source_hash: ?u256,
    /// The amount to increase the balance of the `from` account as part of
    /// a deposit transaction. This is unconditional and is applied to the
    /// `from` account even if the deposit transaction fails since
    /// the deposit is pre-paid on L1.
    mint: ?u128,
    /// Whether or not the transaction is a system transaction.
    is_system_tx: ?bool,
    /// An enveloped EIP-2718 typed transaction. This is used
    /// to compute the L1 tx cost using the L1 block info, as
    /// opposed to requiring downstream apps to compute the cost
    /// externally.
    /// This field is optional to allow the `TxEnviroment` to be constructed
    /// for non-optimism chains when the `optimism` feature is enabled,
    /// but the `ConfigEnviroment` and `optimism` field is set to false.
    enveloped_tx: ?[]u8,

    /// Returns default values for `OptimismFields`
    pub fn default() OptimismFields {
        return .{
            .source_hash = 0,
            .mint = 0,
            .is_system_tx = false,
            .enveloped_tx = &.{},
        };
    }
};

/// The target address kind.
pub const AddressKind = union(enum) {
    /// Simple call `address`.
    call: Address,
    /// Contract creation.
    create,
};

/// The type of analysis to perform.
pub const AnalysisKind = enum {
    /// Do not perform analysis.
    raw,
    /// Perform analysis.
    analyse,
};
