const constants = @import("zabi-utils").constants;
const host = @import("host.zig");
const specification = @import("specification.zig");
const std = @import("std");
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const utils = @import("zabi-utils").utils;
const zabi_types = @import("zabi-types");

const AccessList = transaction.AccessList;
const AccountInfo = host.AccountInfo;
const Address = types.Address;
const Hash = types.Hash;
const SpecId = specification.SpecId;
const TransactionTypes = zabi_types.transactions.TransactionTypes;

/// Set of validation errors from a `EVMEnviroment`.
pub const ValidationErrors = error{
    AccessListNotSupported,
    BlobCreateTransaction,
    BlobGasPriceHigherThanMax,
    BlobVersionNotSupported,
    BlobVersionedHashesNotSupported,
    EmptyBlobs,
    ExpectedBlobPrice,
    GasLimitHigherThanBlock,
    GasPriceLessThanBaseFee,
    InsufficientBalance,
    IntrinsicGasTooLow,
    InvalidChainId,
    InitCodeSizeLimitExceeded,
    InvalidNonce,
    MaxFeePerBlobGasNotSupported,
    PriorityFeeGreaterThanMaxFee,
    SenderHasCode,
    TooManyBlobs,
    UnsupportedTxType,
};

/// The EVM inner enviroment.
pub const EVMEnviroment = struct {
    /// Configuration of the EVM.
    config: ConfigEnviroment = .{},
    /// Configuration of the block the transaction is in.
    block: BlockEnviroment = .{},
    /// Configuration of the transaction that is being executed.
    tx: TxEnviroment = .{},

    /// Creates a default EVM with a specific transaction provided.
    pub fn initDefaultWithTransaction(tx: TxEnviroment) EVMEnviroment {
        return .{
            .config = .{},
            .block = .{},
            .tx = tx,
        };
    }

    /// Calculates the effective gas price of the transaction.
    pub fn effectiveGasPrice(self: *const EVMEnviroment) u256 {
        if (self.tx.gas_priority_fee) |fee| {
            return @min(self.tx.gas_price, self.block.base_fee + fee);
        } else return self.tx.gas_price;
    }

    /// Calculates the `data_fee` of the transaction.
    /// This will return null if cancun is not enabled.
    ///
    /// See EIP-4844:
    /// <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>
    pub fn calculateDataFee(self: *const EVMEnviroment) ?u256 {
        if (self.block.blob_excess_gas_and_price) |fees| {
            return fees.blob_gasprice * self.tx.getTotalBlobGas();
        } else return null;
    }

    /// Calculates the max `data_fee` of the transaction.
    /// This will return null if cancun is not enabled.
    ///
    /// See EIP-4844:
    /// <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4844.md#execution-layer-validation>
    pub fn calculateMaxDataFee(self: *const EVMEnviroment) ?u256 {
        if (self.tx.max_fee_per_blob_gas) |fee| {
            return @truncate(fee * self.tx.getTotalBlobGas());
        } else return null;
    }

    /// Calculates the minimum balance required to execute this transaction.
    /// Returns: gas_limit * gas_price + value + blob_data_fee (if applicable).
    /// For Optimism deposit txs, the `mint` amount is subtracted from required balance.
    pub fn calculateRequiredBalance(self: *const EVMEnviroment) u256 {
        const gas_cost = @as(u256, self.tx.gas_limit) * self.tx.gas_price;
        var total = gas_cost + self.tx.value;

        if (self.calculateMaxDataFee()) |blob_fee| {
            total += blob_fee;
        }

        if (self.tx.optimism) |op| {
            if (op.mint) |mint|
                total -|= @as(u256, mint);
        }

        return total;
    }

    /// Calculates the intrinsic gas cost for the current transaction.
    ///
    /// Intrinsic gas includes:
    /// - Base transaction cost (`constants.TRANSACTION`)
    /// - Calldata byte cost (`TRANSACTION_ZERO_DATA` / `TRANSACTION_NON_ZERO_DATA_*`)
    /// - Contract creation surcharge (`constants.CREATE`) for create transactions
    /// - Access list surcharge (`ACCESS_LIST_ADDRESS` / `ACCESS_LIST_STORAGE_KEY`) when Berlin is enabled
    pub fn calculateIntrinsicGas(self: *const EVMEnviroment) (error{Overflow} || ValidationErrors)!u64 {
        var total: u64 = constants.TRANSACTION;

        const non_zero_cost: u64 = if (self.config.spec_id.enabled(.ISTANBUL))
            constants.TRANSACTION_NON_ZERO_DATA_INIT
        else
            constants.TRANSACTION_NON_ZERO_DATA_FRONTIER;

        for (self.tx.data) |byte| {
            const byte_cost: u64 = if (byte == 0)
                constants.TRANSACTION_ZERO_DATA
            else
                non_zero_cost;

            try addGasCost(&total, byte_cost);
        }

        if (self.tx.transact_to == .create) {
            try addGasCost(&total, constants.CREATE);
            if (self.config.spec_id.enabled(.SHANGHAI)) {
                const init_code_word_cost = try calculateInitCodeWordCost(self.tx.data.len);
                try addGasCost(&total, init_code_word_cost);
            }
        }

        if (self.config.spec_id.enabled(.BERLIN) and self.tx.access_list.len != 0) {
            const access_list_cost = try multiplyGasCost(self.tx.access_list.len, constants.ACCESS_LIST_ADDRESS);
            try addGasCost(&total, access_list_cost);

            for (self.tx.access_list) |entry| {
                const storage_key_cost = try multiplyGasCost(entry.storageKeys.len, constants.ACCESS_LIST_STORAGE_KEY);
                try addGasCost(&total, storage_key_cost);
            }
        }

        return total;
    }

    /// Validates that the transaction gas limit can cover intrinsic gas.
    pub fn validateIntrinsicGas(self: *const EVMEnviroment) ValidationErrors!u64 {
        const intrinsic_gas = self.calculateIntrinsicGas() catch return error.IntrinsicGasTooLow;

        if (self.tx.gas_limit < intrinsic_gas)
            return error.IntrinsicGasTooLow;

        return intrinsic_gas;
    }

    /// Validates the inner block enviroment based on the provided `SpecId`
    pub fn validateBlockEnviroment(
        self: *const EVMEnviroment,
    ) error{ PrevRandaoNotSet, ExcessBlobGasNotSet }!void {
        if (self.config.spec_id.enabled(.MERGE) and self.block.prevrandao == null)
            return error.PrevRandaoNotSet;

        if (self.config.spec_id.enabled(.CANCUN) and self.block.blob_excess_gas_and_price == null)
            return error.ExcessBlobGasNotSet;
    }

    /// Validates the transaction enviroment.
    /// For `CANCUN` enabled and later checks the gas price is not more than the transactions max
    /// and checks if the blob_hashes are correctly set.
    ///
    /// For before `CANCUN` checks if `blob_hashes` and `max_fee_per_blob_gas` are null / empty.
    pub fn validateTransaction(
        self: *const EVMEnviroment,
    ) ValidationErrors!void {
        if (self.tx.chain_id) |chain_id|
            if (chain_id != self.config.chain_id)
                return error.InvalidChainId;

        if (!self.config.disable_block_gas_limit and self.tx.gas_limit > self.block.gas_limit)
            return error.GasLimitHigherThanBlock;

        try self.validateInitCodeRules();

        switch (self.tx.tx_type) {
            .legacy => {
                if (self.tx.blob_hashes.len != 0)
                    return error.BlobVersionedHashesNotSupported;

                if (self.tx.max_fee_per_blob_gas != null)
                    return error.MaxFeePerBlobGasNotSupported;
            },
            .berlin => {
                if (self.tx.blob_hashes.len != 0)
                    return error.BlobVersionedHashesNotSupported;

                if (self.tx.max_fee_per_blob_gas != null)
                    return error.MaxFeePerBlobGasNotSupported;

                if (!self.config.spec_id.enabled(.BERLIN) and self.tx.access_list.len != 0)
                    return error.AccessListNotSupported;
            },
            .london => {
                if (self.tx.blob_hashes.len != 0)
                    return error.BlobVersionedHashesNotSupported;

                if (self.tx.max_fee_per_blob_gas != null)
                    return error.MaxFeePerBlobGasNotSupported;

                if (self.config.spec_id.enabled(.LONDON)) {
                    if (self.tx.gas_priority_fee) |fee|
                        if (fee > self.tx.gas_price)
                            return error.PriorityFeeGreaterThanMaxFee;

                    if (!self.config.disable_base_fee and self.effectiveGasPrice() < self.block.base_fee)
                        return error.GasPriceLessThanBaseFee;
                }
            },
            .cancun => {
                if (self.config.spec_id.enabled(.LONDON)) {
                    if (self.tx.gas_priority_fee) |fee| {
                        if (fee > self.tx.gas_price)
                            return error.PriorityFeeGreaterThanMaxFee;
                    }

                    if (!self.config.disable_base_fee and self.effectiveGasPrice() < self.block.base_fee)
                        return error.GasPriceLessThanBaseFee;
                }

                if (!self.config.spec_id.enabled(.CANCUN)) {
                    if (self.tx.blob_hashes.len != 0)
                        return error.BlobVersionedHashesNotSupported;

                    if (self.tx.max_fee_per_blob_gas != null)
                        return error.MaxFeePerBlobGasNotSupported;

                    return;
                }

                if (self.tx.blob_hashes.len == 0)
                    return error.EmptyBlobs;

                if (self.tx.transact_to == .create)
                    return error.BlobCreateTransaction;

                if (self.tx.blob_hashes.len > constants.MAX_BLOB_NUMBER_PER_BLOCK)
                    return error.TooManyBlobs;

                for (self.tx.blob_hashes) |hashes| {
                    if (hashes[0] != constants.VERSIONED_HASH_VERSION_KZG)
                        return error.BlobVersionNotSupported;
                }

                const max_blob_fee = self.tx.max_fee_per_blob_gas orelse return error.ExpectedBlobPrice;
                const blob_price = self.block.blob_excess_gas_and_price orelse return error.ExpectedBlobPrice;

                if (blob_price.blob_gasprice > max_blob_fee)
                    return error.BlobGasPriceHigherThanMax;
            },
            else => return error.UnsupportedTxType,
        }
    }

    /// Validates Shanghai init code size rules for create transactions.
    ///
    /// Under Shanghai and later, create transaction init code size is limited to
    /// `2 * config.limit_contract_size`.
    pub fn validateInitCodeRules(self: *const EVMEnviroment) ValidationErrors!void {
        if (!self.config.spec_id.enabled(.SHANGHAI))
            return;

        if (self.tx.transact_to != .create)
            return;

        const limit, const overflow = @mulWithOverflow(self.config.limit_contract_size, @as(usize, 2));
        if (@bitCast(overflow))
            return error.InitCodeSizeLimitExceeded;

        if (self.tx.data.len > limit)
            return error.InitCodeSizeLimitExceeded;
    }

    /// Validates the transaction against the sender's account state.
    /// This should be called after `validateTransaction` with access to state.
    ///
    /// Checks performed:
    /// - Nonce matches (unless `tx.nonce` is null)
    /// - Sender has no deployed code (EIP-3607, unless `disable_eip3607` is set)
    /// - Sender has sufficient balance (unless `disable_balance_check` is set)
    pub fn validateAgainstState(
        self: *const EVMEnviroment,
        sender_info: AccountInfo,
    ) ValidationErrors!void {
        if (self.tx.nonce) |expected_nonce| {
            if (sender_info.nonce != expected_nonce)
                return error.InvalidNonce;
        }

        if (!self.config.disable_eip3607) {
            if (!std.mem.eql(u8, &sender_info.code_hash, &constants.EMPTY_HASH))
                return error.SenderHasCode;
        }

        if (!self.config.disable_balance_check) {
            const required = self.calculateRequiredBalance();
            if (sender_info.balance < required)
                return error.InsufficientBalance;
        }
    }

    fn addGasCost(total: *u64, delta: u64) error{Overflow}!void {
        const next, const overflow = @addWithOverflow(total.*, delta);
        if (@bitCast(overflow))
            return error.Overflow;

        total.* = next;
    }

    fn multiplyGasCost(items: usize, unit_cost: u64) error{Overflow}!u64 {
        const count = std.math.cast(u64, items) orelse return error.Overflow;
        const total, const overflow = @mulWithOverflow(count, unit_cost);
        if (@bitCast(overflow))
            return error.Overflow;

        return total;
    }

    fn calculateInitCodeWordCost(data_len: usize) error{Overflow}!u64 {
        const len = std.math.cast(u64, data_len) orelse return error.Overflow;
        const words = std.math.divCeil(u64, len, 32) catch unreachable;
        const cost, const overflow = @mulWithOverflow(words, constants.INITCODE_WORD_COST);

        if (@bitCast(overflow))
            return error.Overflow;

        return cost;
    }
};

/// The EVM Configuration enviroment.
pub const ConfigEnviroment = struct {
    /// The chain id of the EVM. It will be compared with the `tx` chain id.
    chain_id: u64 = 1,
    /// Whether to perform analysis on the bytecode.
    perform_analysis: AnalysisKind = .analyse,
    /// The contract code's size limit.
    ///
    /// By default if should be 24kb as part of the Spurious Dragon upgrade via [EIP-155].
    ///
    /// [EIP-155]: https://eips.ethereum.org/EIPS/eip-155
    limit_contract_size: usize = 0x600,
    /// The max size that the memory can grow too with failing with `OutOfGas` errors.
    memory_limit: u64 = std.math.maxInt(u32),
    /// Skips balance checks if enabled. Adds transaction cost to ensure execution doesn't fail.
    disable_balance_check: bool = false,
    /// There are use cases where it's allowed to provide a gas limit that's higher than a block's gas limit.
    /// To that end, you can disable the block gas limit validation.
    disable_block_gas_limit: bool = false,
    /// EIP-3607 rejects transactions from senders with deployed code. In development, it can be desirable to simulate
    /// calls from contracts, which this setting allows.
    disable_eip3607: bool = false,
    /// Disables all gas refunds. This is useful when using chains that have gas refunds disabled e.g. Avalanche.
    /// Reasoning behind removing gas refunds can be found in EIP-3298.
    disable_gas_refund: bool = false,
    /// Disables base fee checks for EIP-1559 transactions.
    /// This is useful for testing method calls with zero gas price.
    disable_base_fee: bool = false,
    /// Disables the payout of the reward to the beneficiary.
    disable_beneficiary_reward: bool = false,
    /// The hardfork specification to use for opcode availability and gas costs.
    spec_id: SpecId = .LATEST,
};

/// Type that representes the excess blob gas and it's price.
pub const BlobExcessGasAndPrice = struct {
    blob_gasprice: u256 = 0,
    blob_excess_gas: u256 = 0,

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
    number: u256 = 0,
    /// Coinbase or miner or address that created and signed the block.
    ///
    /// This is the receiver address of all the gas spent in the block.
    coinbase: Address = [_]u8{0} ** 20,
    /// The timestamp of the block in seconds since the UNIX epoch.
    timestamp: u256 = 1,
    /// The gas limit of the block.
    gas_limit: u256 = 0,
    /// The base fee per gas, added in the London upgrade with [EIP-1559].
    ///
    /// [EIP-1559]: https://eips.ethereum.org/EIPS/eip-1559
    base_fee: u256 = 0,
    /// The difficulty of the block.
    ///
    /// Unused after the Paris (AKA the merge) upgrade, and replaced by `prevrandao`.
    difficulty: u256 = 0,
    /// The output of the randomness beacon provided by the beacon chain.
    ///
    /// Replaces `difficulty` after the Paris (AKA the merge) upgrade with [EIP-4399].
    ///
    /// NOTE: `prevrandao` can be found in a block in place of `mix_hash`.
    ///
    /// [EIP-4399]: https://eips.ethereum.org/EIPS/eip-4399
    prevrandao: ?u256 = 0,
    /// Excess blob gas and blob gasprice. Check `BlobExcessGasAndPrice`
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    blob_excess_gas_and_price: ?BlobExcessGasAndPrice = .{},
};

/// The transaction enviroment.
pub const TxEnviroment = struct {
    tx_type: TransactionTypes = .london,
    /// The signer of this transaction.
    caller: Address = [_]u8{0} ** 20,
    /// The gas limit for this transaction.
    gas_limit: u64 = 0,
    /// The gas price for this transaction.
    gas_price: u256 = 0,
    /// The target of this transaction.
    transact_to: AddressKind = .{ .call = [_]u8{1} ** 20 },
    /// The value sent in this transaction.
    value: u256 = 0,
    /// The data of the transaction.
    data: []u8 = &.{},
    /// The nonce of this transaction.
    ///
    /// Caution: If set to `null`, then nonce validation against the account's nonce is skipped.
    nonce: ?u64 = 0,
    /// The chain ID of the transaction. If set to `null`, no checks are performed.
    ///
    /// Incorporated as part of the Spurious Dragon upgrade via [EIP-155].
    ///
    /// [EIP-155]: https://eips.ethereum.org/EIPS/eip-155
    chain_id: ?u64 = 1,
    /// A list of addresses and storage keys that the transaction plans to access.
    ///
    /// Added in [EIP-2930].
    ///
    /// [EIP-2930]: https://eips.ethereum.org/EIPS/eip-2930
    access_list: []const AccessList = &.{},
    /// The priority fee per gas.
    ///
    /// Incorporated as part of the London upgrade via [EIP-1559].
    ///
    /// [EIP-1559]: https://eips.ethereum.org/EIPS/eip-1559
    gas_priority_fee: ?u256 = 0,
    /// The list of blob versioned hashes. Per EIP there should be at least
    /// one blob present if `max_fee_per_blob_gas` isn't null.
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    blob_hashes: []const Hash = &.{},
    /// The max fee per blob gas.
    ///
    /// Incorporated as part of the Cancun upgrade via [EIP-4844].
    ///
    /// [EIP-4844]: https://eips.ethereum.org/EIPS/eip-4844
    max_fee_per_blob_gas: ?u256 = null,
    /// `Optimism` dedicated fields.
    optimism: ?OptimismFields = null,

    /// Gets the total blob gas in this `TxEnviroment`.
    pub fn getTotalBlobGas(self: *const TxEnviroment) u64 {
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
    source_hash: ?u256 = 0,
    /// The amount to increase the balance of the `from` account as part of
    /// a deposit transaction. This is unconditional and is applied to the
    /// `from` account even if the deposit transaction fails since
    /// the deposit is pre-paid on L1.
    mint: ?u128 = 0,
    /// Whether or not the transaction is a system transaction.
    is_system_tx: ?bool = false,
    /// An enveloped EIP-2718 typed transaction. This is used
    /// to compute the L1 tx cost using the L1 block info, as
    /// opposed to requiring downstream apps to compute the cost
    /// externally.
    /// This field is optional to allow the `TxEnviroment` to be constructed
    /// for non-optimism chains when the `optimism` feature is enabled,
    /// but the `ConfigEnviroment` and `optimism` field is set to false.
    enveloped_tx: ?[]u8 = null,
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
