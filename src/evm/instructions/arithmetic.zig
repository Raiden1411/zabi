const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Stack = @import("../../utils/stack.zig").Stack;
const Interpreter = @import("../Interpreter.zig");

/// Performs add instruction for the interpreter.
/// ADD -> 0x01
pub fn addInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const addition = first +% second;

    try self.stack.pushUnsafe(addition);
}
/// Performs div instruction for the interpreter.
/// DIV -> 0x04
pub fn divInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    std.debug.assert(second != 0); // division by 0

    const div = @divFloor(first, second);

    try self.stack.pushUnsafe(div);
}
/// Performs exponent instruction for the interpreter.
/// EXP -> 0x0A
pub fn exponentInstruction(self: *Interpreter) !void {
    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const exp_gas = try gas.calculateExponentCost(second, self.spec);
    try self.gas_tracker.updateTracker(exp_gas);

    const exp = std.math.pow(u256, first, second);
    try self.stack.pushUnsafe(exp);
}
/// Performs addition + mod instruction for the interpreter.
/// ADDMOD -> 0x08
pub fn modAdditionInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();
    const third = try self.stack.tryPopUnsafe();

    std.debug.assert(third != 0); // remainder division by 0

    const add = first +% second;
    const mod = @mod(add, third);

    try self.stack.pushUnsafe(mod);
}
/// Performs mod instruction for the interpreter.
/// MOD -> 0x06
pub fn modInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    std.debug.assert(second != 0); // remainder division by 0

    const mod = @mod(first, second);

    try self.stack.pushUnsafe(mod);
}
/// Performs mul + mod instruction for the interpreter.
/// MULMOD -> 0x09
pub fn modMultiplicationInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();
    const third = try self.stack.tryPopUnsafe();

    std.debug.assert(third != 0); // remainder division by 0

    const mul = first *% second;
    const mod = @mod(mul, third);

    try self.stack.pushUnsafe(mod);
}
/// Performs mul instruction for the interpreter.
/// MUL -> 0x02
pub fn mulInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const mul = first *% second;

    try self.stack.pushUnsafe(mul);
}
/// Performs signed division instruction for the interpreter.
/// SDIV -> 0x05
pub fn signedDivInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // division by 0

    const div: u256 = @bitCast(@divFloor(casted_first, casted_second));

    try self.stack.pushUnsafe(div);
}
/// Performs signextend instruction for the interpreter.
/// SIGNEXTEND -> 0x0B
pub fn signExtendInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const ext = try self.stack.tryPopUnsafe();
    const x = try self.stack.tryPopUnsafe();

    if (ext < 31) {
        const bit_index: usize = 8 * @as(usize, @intCast(ext)) + 7;
        const mask = std.math.shl(u256, 1, bit_index);
        const value_mask = mask - 1;

        const neg = (x & mask) != 0;
        try self.stack.pushUnsafe(if (neg) x | ~value_mask else x & value_mask);
    } else {
        try self.stack.pushUnsafe(x);
    }
}
/// Performs sub instruction for the interpreter.
/// SMOD -> 0x07
pub fn signedModInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // remainder division by 0

    const div = @mod(casted_first, casted_second);

    try self.stack.pushUnsafe(@bitCast(div));
}
/// Performs sub instruction for the interpreter.
/// SUB -> 0x03
pub fn subInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const sub = first -% second;

    try self.stack.pushUnsafe(sub);
}
