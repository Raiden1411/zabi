const constants = @import("../utils/constants.zig");
const host = @import("host.zig");
const mem = @import("memory.zig");
const utils = @import("../utils/utils.zig");

const SpecId = @import("specification.zig").SpecId;
const SelfDestructResult = host.SelfDestructResult;

pub const QUICK_STEP: u64 = 2;
pub const FASTEST_STEP: u64 = 3;
pub const FAST_STEP: u64 = 5;
pub const MID_STEP: u64 = 8;
pub const SLOW_STEP: u64 = 10;
pub const EXT_STEP: u64 = 20;

pub const JUMPDEST: u64 = 1;
pub const SELFDESTRUCT: i64 = 24000;
pub const CREATE: u64 = 32000;
pub const CALLVALUE: u64 = 9000;
pub const NEWACCOUNT: u64 = 25000;
pub const LOG: u64 = 375;
pub const LOGDATA: u64 = 8;
pub const LOGTOPIC: u64 = 375;
pub const KECCAK256: u64 = 30;
pub const KECCAK256WORD: u64 = 6;
pub const BLOCKHASH: u64 = 20;
pub const CODEDEPOSIT: u64 = 200;
pub const CONDITION_JUMP_GAS: u64 = 4;
pub const RETF_GAS: u64 = 4;
pub const DATA_LOAD_GAS: u64 = 4;

/// EIP-1884: Repricing for trie-size-dependent opcodes
pub const ISTANBUL_SLOAD_GAS: u64 = 800;
pub const SSTORE_SET: u64 = 20000;
pub const SSTORE_RESET: u64 = 5000;
pub const REFUND_SSTORE_CLEARS: i64 = 15000;

pub const TRANSACTION_ZERO_DATA: u64 = 4;
pub const TRANSACTION_NON_ZERO_DATA_INIT: u64 = 16;
pub const TRANSACTION_NON_ZERO_DATA_FRONTIER: u64 = 68;

pub const EOF_CREATE_GAS: u64 = 32000;

// berlin eip2929 constants
pub const ACCESS_LIST_ADDRESS: u64 = 2400;
pub const ACCESS_LIST_STORAGE_KEY: u64 = 1900;
pub const COLD_SLOAD_COST: u64 = 2100;
pub const COLD_ACCOUNT_ACCESS_COST: u64 = 2600;
pub const WARM_STORAGE_READ_COST: u64 = 100;
pub const WARM_SSTORE_RESET: u64 = SSTORE_RESET - COLD_SLOAD_COST;

/// EIP-3860 : Limit and meter initcode
pub const INITCODE_WORD_COST: u64 = 2;

pub const CALL_STIPEND: u64 = 2300;

/// Gas tracker used to track gas usage by the EVM.
pub const GasTracker = struct {
    /// The gas size limit that the interpreter can run.
    gas_limit: u64,
    /// The amount of gas that has already been used.
    used_amount: u64,
    /// The amount of gas to refund to the caller.
    refund_amount: i64,

    /// Sets the tracker's initial state.
    pub fn init(gas_limit: u64) GasTracker {
        return .{
            .gas_limit = gas_limit,
            .used_amount = 0,
            .refund_amount = 0,
        };
    }
    /// Returns the remaining gas that can be used.
    pub fn availableGas(self: GasTracker) u64 {
        return self.gas_limit - self.used_amount;
    }
    /// Updates the gas tracker based on the opcode cost.
    pub inline fn updateTracker(self: *GasTracker, cost: u64) error{ OutOfGas, GasOverflow }!void {
        const total, const overflow = @addWithOverflow(self.used_amount, cost);

        if (@bitCast(overflow))
            return error.GasOverflow;

        if (total > self.gas_limit)
            return error.OutOfGas;

        self.used_amount = total;
    }
};
/// Calculates the gas cost for the `CALL` opcode.
pub inline fn calculateCallCost(spec: SpecId, values_transfered: bool, is_cold: bool, new_account: bool) u64 {
    var gas: u64 = if (spec.enabled(.BERLIN)) warmOrColdCost(is_cold) else if (spec.enabled(.TANGERINE)) 700 else 40;

    if (values_transfered)
        gas += CALLVALUE;

    if (new_account) {
        if (spec.enabled(.SPURIOUS_DRAGON)) {
            if (values_transfered)
                gas += NEWACCOUNT;
        } else {
            gas += NEWACCOUNT;
        }
    }

    return gas;
}
/// Calculates the gas cost for the `EXTCODESIZE` opcode.
pub inline fn calculateCodeSizeCost(spec: SpecId, is_cold: bool) u64 {
    if (spec.enabled(.BERLIN))
        return warmOrColdCost(is_cold);

    if (spec.enabled(.TANGERINE))
        return 700;

    return 20;
}
/// Calculates the gas cost per `Memory` word.
/// Returns null in case of overflow.
pub inline fn calculateCostPerMemoryWord(length: u64, multiple: u64) ?u64 {
    const result, const overflow = @mulWithOverflow(multiple, mem.availableWords(length));

    if (@bitCast(overflow))
        return null;

    return result;
}
/// Calculates the cost of using the `CREATE` opcode.
/// **PANICS** if the gas cost overflows
pub inline fn calculateCreateCost(length: u64) u64 {
    return calculateCostPerMemoryWord(length, INITCODE_WORD_COST) orelse @panic("Init contract code cost overflow");
}
/// Calculates the cost of using the `CREATE2` opcode.
/// Returns null in case of overflow.
pub inline fn calculateCreate2Cost(length: u64) ?u64 {
    const word_cost = calculateCostPerMemoryWord(length, KECCAK256WORD);
    if (word_cost) |word| {
        const result, const overflow = @addWithOverflow(CREATE, word);

        if (overflow)
            return null;

        return result;
    } else return null;
}
/// Calculates the gas used for the `EXP` opcode.
pub inline fn calculateExponentCost(exp: u256, spec: SpecId) !u64 {
    const size = utils.computeSize(exp);
    const gas: u8 = if (spec.enabled(.SPURIOUS_DRAGON)) @intCast(50) else @intCast(10);

    const exp_gas, const overflow = @addWithOverflow(gas * size, 10); // 10 is the EXP instruction gas cost.

    if (overflow != 0)
        return error.Overflow;

    return exp_gas;
}
/// Calculates the cost of using the `KECCAK256` opcode.
/// Returns null in case of overflow.
pub inline fn calculateKeccakCost(length: u64) ?u64 {
    const word_cost = calculateCostPerMemoryWord(length, KECCAK256WORD);
    if (word_cost) |word| {
        const result, const overflow = @addWithOverflow(KECCAK256, word);

        if (overflow)
            return null;

        return result;
    } else return null;
}
/// Calculates the gas cost for a LOG instruction.
pub inline fn calculateLogCost(size: u8, length: u64) ?u64 {
    const topics: u64 = LOGTOPIC * size;
    const data_cost, const data_overflow = @mulWithOverflow(LOGDATA, length);

    if (data_overflow)
        return null;

    const value, const overflow = @addWithOverflow(LOG, data_cost);

    if (overflow)
        return null;

    const log, const log_overflow = @addWithOverflow(value, topics);

    if (log_overflow)
        return null;

    return log;
}
/// Calculates the memory expansion cost based on the provided `word_count`
pub inline fn calculateMemoryCost(count: u64) u64 {
    const cost = utils.saturatedMultiplication(u64, 3, count);

    return utils.saturatedAddition(u64, cost, @divFloor(utils.saturatedMultiplication(u64, count, count), 512));
}
/// Calculates the cost of a memory copy.
pub inline fn calculateMemoryCopyLowCost(length: u64) ?u64 {
    const word_cost = calculateCostPerMemoryWord(length, 3);

    if (word_cost) |word| {
        const result, const overflow = @addWithOverflow(word, 3);

        if (@bitCast(overflow))
            return null;

        return result;
    } else return null;
}
/// Calculates the cost of the `SSTORE` opcode after the `FRONTIER` spec.
pub inline fn calculateFrontierSstoreCost(current: u256, new: u256) u64 {
    if (current == 0 and new != 0)
        return SSTORE_SET;

    return SSTORE_RESET;
}
/// Calculates the cost of the `SSTORE` opcode after the `ISTANBUL` spec.
pub inline fn calculateIstanbulSstoreCost(original: u256, current: u256, new: u256) u64 {
    if (new == current)
        return WARM_STORAGE_READ_COST;

    if (original == current and original == 0)
        return SSTORE_SET;

    if (original == current)
        return WARM_SSTORE_RESET;

    return WARM_STORAGE_READ_COST;
}
/// Calculate the cost of an `SLOAD` opcode based on the spec and if the access is cold
/// or warm if the `BERLIN` spec is enabled.
pub inline fn calculateSloadCost(spec: SpecId, is_cold: bool) u64 {
    if (spec.enabled(.BERLIN)) {
        return if (is_cold) COLD_ACCOUNT_ACCESS_COST else WARM_STORAGE_READ_COST;
    }

    if (spec.enabled(.ISTANBUL))
        return ISTANBUL_SLOAD_GAS;

    if (spec.enabled(.TANGERINE))
        return 200;

    return 50;
}
/// Calculate the cost of an `SSTORE` opcode based on the spec, if the access is cold
/// and the value in storage. Returns null if the spec is `ISTANBUL` enabled and the provided
/// gas is lower than `CALL_STIPEND`.
pub inline fn calculateSstoreCost(spec: SpecId, original: u256, current: u256, new: u256, gas: u64, is_cold: bool) ?u64 {
    if (spec.enabled(.ISTANBUL) and gas <= CALL_STIPEND)
        return null;

    if (spec.enabled(.BERLIN)) {
        var gas_cost = calculateIstanbulSstoreCost(original, current, new);

        if (is_cold)
            gas_cost += COLD_SLOAD_COST;

        return gas_cost;
    }

    if (spec.enabled(.ISTANBUL))
        return calculateIstanbulSstoreCost(original, current, new);

    return calculateFrontierSstoreCost(current, new);
}
/// Calculate the refund of an `SSTORE` opcode.
pub inline fn calculateSstoreRefund(spec: SpecId, original: u256, current: u256, new: u256) i64 {
    if (spec.enabled(.ISTANBUL)) {
        const sstore_clears_schedule: i64 = if (spec.enabled(.LONDON)) SSTORE_RESET - COLD_SLOAD_COST + ACCESS_LIST_STORAGE_KEY else REFUND_SSTORE_CLEARS;

        if (current == new)
            return 0;

        if (original == current and new == 0)
            return sstore_clears_schedule;

        var refund = 0;

        if (original != 0) {
            if (current == 0) {
                refund -= sstore_clears_schedule;
            } else refund += sstore_clears_schedule;
        }

        if (original == new) {
            const reset, const sload: struct { i64, i64 } = if (spec.enabled(.BERLIN)) .{ SSTORE_RESET - COLD_SLOAD_COST, WARM_STORAGE_READ_COST } else .{
                SSTORE_RESET,
                calculateSloadCost(spec, false),
            };

            if (original == 0) {
                refund += SSTORE_RESET - sload;
            } else refund += reset - sload;
        }

        return refund;
    }

    return if (current != 0 and new == 0) REFUND_SSTORE_CLEARS else 0;
}
/// Calculate the cost of an `SELFDESTRUCT` opcode based on the spec and it's result.
pub inline fn calculateSelfDestructCost(spec: SpecId, result: SelfDestructResult) u64 {
    const charge_topup = if (spec.enabled(.SPURIOUS_DRAGON)) result.had_value and !result.target_exists else !result.target_exists;

    const gas_topup = if (spec.enabled(.TANGERINE) and charge_topup) 25000 else 0;
    const gas_opcode = if (spec.enabled(.TANGERINE)) 5000 else 0;
    var gas = gas_topup + gas_opcode;

    if (spec.enabled(.BERLIN) and result.is_cold)
        gas += COLD_ACCOUNT_ACCESS_COST;

    return gas;
}
/// Returns the gas cost for reading from a `warm` or `cold` storage slot.
pub inline fn warmOrColdCost(cold: bool) u64 {
    return if (cold) COLD_ACCOUNT_ACCESS_COST else WARM_STORAGE_READ_COST;
}
