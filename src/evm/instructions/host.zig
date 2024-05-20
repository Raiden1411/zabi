const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../interpreter.zig");

/// Runs the balance opcode for the interpreter.
/// 0x31 -> BALANCE
pub fn balanceInstruction(self: *Interpreter) !void {
    const address = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const bal, const is_cold = self.host.balance(address) orelse return error.UnexpectedError;

    const gas_usage: u64 = blk: {
        if (self.spec.enabled(.BERLIN))
            break :blk gas.warmOrColdCost(is_cold);

        if (self.spec.enabled(.ISTANBUL))
            break :blk 700;

        if (self.spec.enabled(.TANGERINE))
            break :blk 400;

        break :blk 20;
    };

    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(bal);
    self.program_counter += 1;
}
/// Runs the blockhash opcode for the interpreter.
/// 0x40 -> BLOCKHASH
pub fn blockHashInstruction(self: *Interpreter) !void {
    _ = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const num = self.host.getEnviroment().block.number;

    const hash = self.host.blockHash(num) orelse return error.UnexpectedError;

    try self.gas_tracker.updateTracker(gas.BLOCKHASH);

    try self.stack.pushUnsafe(@bitCast(hash));
    self.program_counter += 1;
}
/// Runs the extcodehash opcode for the interpreter.
/// 0x3F -> EXTCODEHASH
pub fn extCodeHashInstruction(self: *Interpreter) !void {
    const address = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const code_hash, const is_cold = self.host.codeHash(address) orelse return error.UnexpectedError;

    const gas_usage: u64 = blk: {
        if (self.spec.enabled(.BERLIN))
            break :blk gas.warmOrColdCost(is_cold);

        if (self.spec.enabled(.ISTANBUL))
            break :blk 700;

        break :blk 400;
    };

    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(@bitCast(code_hash));
    self.program_counter += 1;
}
/// Runs the extcodesize opcode for the interpreter.
/// 0x3B -> EXTCODESIZE
pub fn extCodeSizeInstruction(self: *Interpreter) !void {
    const address = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const code, const is_cold = self.host.code(address) orelse return error.UnexpectedError;

    const gas_usage = gas.calculateCodeSizeCost(self.spec, is_cold);
    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(code.len);
    self.program_counter += 1;
}
/// Runs the selfbalance opcode for the interpreter.
/// 0x47 -> SELFBALANCE
pub fn selfBalanceInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.ISTANBUL))
        return error.InstructionNotEnabled;

    const bal, _ = self.host.balance(self.contract.target_address) orelse return error.UnexpectedError;
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    try self.stack.pushUnsafe(bal);
    self.program_counter += 1;
}
/// Runs the selfbalance opcode for the interpreter.
/// 0xFF -> SELFDESTRUCT
pub fn selfDestructInstruction(self: *Interpreter) !void {
    std.debug.assert(!self.is_static); // requires non static calls.

    const address = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const result = try self.host.selfDestruct(self.contract.target_address, address);

    if (self.spec.enabled(.LONDON) and !result.previously_destroyed)
        self.gas_tracker.refund_amount += 24000;

    const gas_usage = gas.calculateSelfDestructCost(self.spec, result);
    try self.gas_tracker.updateTracker(gas_usage);

    self.status = .SelfDestructed;
}
/// Runs the sload opcode for the interpreter.
/// 0x54 -> SLOAD
pub fn sloadInstruction(self: *Interpreter) !void {
    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const value, const is_cold = try self.host.sload(self.contract.target_address, index);

    const gas_usage = gas.calculateSloadCost(self.spec, is_cold);
    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(value);
    self.program_counter += 1;
}
/// Runs the sstore opcode for the interpreter.
/// 0x55 -> SSTORE
pub fn sstoreInstruction(self: *Interpreter) !void {
    std.debug.assert(!self.is_static); // Requires non static calls.

    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const value = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const result = try self.host.sstore(self.contract.target_address, index, value);
    const gas_remaining = self.gas_tracker.gas_limit - self.gas_tracker.used_amount;

    const gas_cost = gas.calculateSstoreCost(self.spec, result.original_value, result.present_value, result.new_value, gas_remaining, result.is_cold);

    try self.gas_tracker.updateTracker(gas_cost);
    self.gas_tracker.refund_amount = gas.calculateSstoreRefund(self.spec, result.original_value, result.present_value, result.new_value);

    self.program_counter += 1;
}
/// Runs the tload opcode for the interpreter.
/// 0x5C -> TLOAD
pub fn tloadInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const load = try self.host.tload(self.contract.target_address, index);
    try self.gas_tracker.updateTracker(gas.WARM_STORAGE_READ_COST);

    try self.stack.pushUnsafe(load orelse 0);

    self.program_counter += 1;
}
/// Runs the tstore opcode for the interpreter.
/// 0x5D -> TSTORE
pub fn tstoreInstruction(self: *Interpreter) !void {
    std.debug.assert(!self.is_static); // requires non static calls.

    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const value = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.host.tstore(self.contract.target_address, index, value);
    try self.gas_tracker.updateTracker(gas.WARM_STORAGE_READ_COST);

    self.program_counter += 1;
}
