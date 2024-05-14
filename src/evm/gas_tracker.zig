const utils = @import("../utils/utils.zig");

pub const GasQuickStep: u64 = 2;
pub const GasFastestStep: u64 = 3;
pub const GasFastStep: u64 = 5;
pub const GasMidStep: u64 = 8;
pub const GasSlowStep: u64 = 10;
pub const GasExtStep: u64 = 20;

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
    /// Updates the gas tracker based on the opcode cost.
    pub inline fn updateTracker(self: GasTracker, cost: u64) error{OutOfGas}!void {
        const total = self.used_amount + cost;

        if (total > self.gas_limit)
            return error.OutOfGas;

        self.used_amount = total;
    }
};
/// Gets the value of the gas cost for a `Call` opcode.
pub inline fn callGasCost(gas_limit: u64, call_cost: u64) error{OutOfGas}!u64 {
    const avaliable_gas = gas_limit - call_cost;

    const gas = avaliable_gas - (avaliable_gas / 64);

    if (gas < call_cost) {
        return gas;
    }

    return error.OutOfGas;
}
/// Gets the gas used for the `EXP` opcode.
pub inline fn exponentGasCost(exp: u256) u64 {
    const size = utils.computeSize(exp);
    const gas = size * 50; // EIP158 (Spurious Dragon)

    const exp_gas, const overflow = @addWithOverflow(gas, 10); // 10 is the EXP instruction gas cost.

    if (overflow != 0)
        return error.Overflow;

    return exp_gas;
}
