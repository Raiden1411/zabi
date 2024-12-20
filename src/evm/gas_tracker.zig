const constants = zabi_utils.constants;
const host = @import("host.zig");
const mem = @import("memory.zig");
const testing = @import("std").testing;
const utils = zabi_utils.utils;
const zabi_utils = @import("zabi-utils");

const SpecId = @import("specification.zig").SpecId;
const SelfDestructResult = host.SelfDestructResult;

/// Gas tracker used to track gas usage by the EVM.
pub const GasTracker = struct {
    /// Set of errors that can be returned while updating the tracker.
    pub const Error = error{ OutOfGas, GasOverflow };

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
    pub inline fn updateTracker(self: *GasTracker, cost: u64) GasTracker.Error!void {
        const total, const overflow = @addWithOverflow(self.used_amount, cost);

        if (@bitCast(overflow)) {
            @branchHint(.cold);
            return error.GasOverflow;
        }

        if (total > self.gas_limit) {
            @branchHint(.cold);
            return error.OutOfGas;
        }

        self.used_amount = total;
    }
};
/// Calculates the gas cost for the `CALL` opcode.
pub inline fn calculateCallCost(spec: SpecId, values_transfered: bool, is_cold: bool, new_account: bool) u64 {
    var gas: u64 = if (spec.enabled(.BERLIN)) warmOrColdCost(is_cold) else if (spec.enabled(.TANGERINE)) 700 else 40;

    if (values_transfered)
        gas += constants.CALLVALUE;

    if (new_account) {
        if (spec.enabled(.SPURIOUS_DRAGON)) {
            if (values_transfered)
                gas += constants.NEWACCOUNT;
        } else {
            gas += constants.NEWACCOUNT;
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
    return calculateCostPerMemoryWord(length, constants.INITCODE_WORD_COST) orelse @panic("Init contract code cost overflow");
}
/// Calculates the cost of using the `CREATE2` opcode.
/// Returns null in case of overflow.
pub inline fn calculateCreate2Cost(length: u64) ?u64 {
    const word_cost = calculateCostPerMemoryWord(length, constants.KECCAK256WORD);
    if (word_cost) |word| {
        const result, const overflow = @addWithOverflow(constants.CREATE, word);

        if (@bitCast(overflow))
            return null;

        return result;
    } else return null;
}
/// Calculates the gas used for the `EXP` opcode.
pub inline fn calculateExponentCost(exp: u256, spec: SpecId) error{Overflow}!u64 {
    const size = utils.computeSize(exp);
    const gas: u8 = if (spec.enabled(.SPURIOUS_DRAGON)) @intCast(50) else @intCast(10);

    const exp_gas, const overflow = @addWithOverflow(gas * size, 10); // 10 is the EXP instruction gas cost.

    if (@bitCast(overflow))
        return error.Overflow;

    return exp_gas;
}
/// Calculates the gas used for the `EXTCODECOPY` opcode.
pub inline fn calculateExtCodeCopyCost(spec: SpecId, len: u64, is_cold: bool) ?u64 {
    const word_cost = calculateCostPerMemoryWord(len, 3);

    if (word_cost) |cost| {
        const gas: u64 = if (spec.enabled(.BERLIN)) warmOrColdCost(is_cold) else if (spec.enabled(.TANGERINE)) @intCast(700) else @intCast(20);

        const result, const overflow = @addWithOverflow(gas, cost);

        if (@bitCast(overflow))
            return null;

        return result;
    } else return null;
}
/// Calculates the cost of using the `KECCAK256` opcode.
/// Returns null in case of overflow.
pub inline fn calculateKeccakCost(length: u64) ?u64 {
    const word_cost = calculateCostPerMemoryWord(length, constants.KECCAK256WORD);
    if (word_cost) |word| {
        const result, const overflow = @addWithOverflow(constants.KECCAK256, word);

        if (@bitCast(overflow))
            return null;

        return result;
    } else return null;
}
/// Calculates the gas cost for a LOG instruction.
pub inline fn calculateLogCost(size: u8, length: u64) ?u64 {
    const topics: u64 = constants.LOGTOPIC * size;
    const data_cost, const data_overflow = @mulWithOverflow(constants.LOGDATA, length);

    if (@bitCast(data_overflow))
        return null;

    const value, const overflow = @addWithOverflow(constants.LOG, data_cost);

    if (@bitCast(overflow))
        return null;

    const log, const log_overflow = @addWithOverflow(value, topics);

    if (@bitCast(log_overflow))
        return null;

    return log;
}
/// Calculates the memory expansion cost based on the provided `word_count`
pub inline fn calculateMemoryCost(count: u64) u64 {
    return (3 *| count) +| @divFloor(count *| count, 512);
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
        return constants.SSTORE_SET;

    return constants.SSTORE_RESET;
}
/// Calculates the cost of the `SSTORE` opcode after the `ISTANBUL` spec.
pub inline fn calculateIstanbulSstoreCost(original: u256, current: u256, new: u256) u64 {
    if (new == current)
        return constants.WARM_STORAGE_READ_COST;

    if (original == current and original == 0)
        return constants.SSTORE_SET;

    if (original == current)
        return constants.WARM_SSTORE_RESET;

    return constants.WARM_STORAGE_READ_COST;
}
/// Calculate the cost of an `SLOAD` opcode based on the spec and if the access is cold
/// or warm if the `BERLIN` spec is enabled.
pub inline fn calculateSloadCost(spec: SpecId, is_cold: bool) u64 {
    if (spec.enabled(.BERLIN)) {
        return if (is_cold) constants.COLD_ACCOUNT_ACCESS_COST else constants.WARM_STORAGE_READ_COST;
    }

    if (spec.enabled(.ISTANBUL))
        return constants.ISTANBUL_SLOAD_GAS;

    if (spec.enabled(.TANGERINE))
        return 200;

    return 50;
}
/// Calculate the cost of an `SSTORE` opcode based on the spec, if the access is cold
/// and the value in storage. Returns null if the spec is `ISTANBUL` enabled and the provided
/// gas is lower than `CALL_STIPEND`.
pub inline fn calculateSstoreCost(spec: SpecId, original: u256, current: u256, new: u256, gas: u64, is_cold: bool) ?u64 {
    if (spec.enabled(.ISTANBUL) and gas <= constants.CALL_STIPEND)
        return null;

    if (spec.enabled(.BERLIN)) {
        var gas_cost = calculateIstanbulSstoreCost(original, current, new);

        if (is_cold)
            gas_cost += constants.COLD_SLOAD_COST;

        return gas_cost;
    }

    if (spec.enabled(.ISTANBUL))
        return calculateIstanbulSstoreCost(original, current, new);

    return calculateFrontierSstoreCost(current, new);
}
/// Calculate the refund of an `SSTORE` opcode.
pub inline fn calculateSstoreRefund(spec: SpecId, original: u256, current: u256, new: u256) i64 {
    if (spec.enabled(.ISTANBUL)) {
        if (current == new)
            return 0;

        if (original == current and new == 0)
            return constants.sstore_clears_schedule;

        var refund: i64 = 0;

        if (original != 0) {
            if (current == 0) {
                refund -= constants.sstore_clears_schedule;
            } else refund += constants.sstore_clears_schedule;
        }

        if (original == new) {
            const result: struct { i64, i64 } = if (spec.enabled(.BERLIN)) .{ constants.SSTORE_RESET - constants.COLD_SLOAD_COST, constants.WARM_STORAGE_READ_COST } else .{
                constants.SSTORE_RESET,
                @intCast(calculateSloadCost(spec, false)),
            };

            if (original == 0) {
                refund += @as(i64, @intCast(constants.SSTORE_RESET)) - result[1];
            } else refund += result[0] - result[1];
        }

        return refund;
    }

    return if (current != 0 and new == 0) constants.REFUND_SSTORE_CLEARS else 0;
}
/// Calculate the cost of an `SELFDESTRUCT` opcode based on the spec and it's result.
pub inline fn calculateSelfDestructCost(spec: SpecId, result: SelfDestructResult) u64 {
    const charge_topup = if (spec.enabled(.SPURIOUS_DRAGON)) result.had_value and !result.target_exists else !result.target_exists;

    const gas_topup: u64 = if (spec.enabled(.TANGERINE) and charge_topup) 25000 else 0;
    const gas_opcode: u64 = if (spec.enabled(.TANGERINE)) 5000 else 0;
    var gas: u64 = gas_topup + gas_opcode;

    if (spec.enabled(.BERLIN) and result.is_cold)
        gas += constants.COLD_ACCOUNT_ACCESS_COST;

    return gas;
}
/// Returns the gas cost for reading from a `warm` or `cold` storage slot.
pub inline fn warmOrColdCost(cold: bool) u64 {
    return if (cold) constants.COLD_ACCOUNT_ACCESS_COST else constants.WARM_STORAGE_READ_COST;
}
