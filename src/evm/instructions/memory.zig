const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../interpreter.zig");

/// Runs the mcopy opcode for the interpreter.
/// 0x5E -> MCOPY
pub fn mcopyInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const destination = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const source = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (length > comptime std.math.maxInt(u64))
        return error.Overflow;

    const cost = try gas.calculateMemoryCopyLowCost(@intCast(length));
    try self.gas_tracker.updateTracker(cost orelse return error.OutOfGas);

    if (length == 0)
        return;

    if (source > comptime std.math.maxInt(u64))
        return error.Overflow;
    if (destination > comptime std.math.maxInt(u64))
        return error.Overflow;

    const new_size: u64 = @truncate(@max(destination, source) + length);
    try self.resize(new_size);

    self.memory.memoryCopy(@intCast(destination), @intCast(source), @intCast(length));
    self.program_counter += 1;
}
/// Runs the mload opcode for the interpreter.
/// 0x51 -> MLOAD
pub fn mloadInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (offset > comptime std.math.maxInt(u64))
        return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size: u64 = @truncate(offset + 32);
    try self.resize(new_size);

    const load = try self.memory.getMemoryWord(offset);
    try self.stack.pushUnsafe(@bitCast(load));
    self.program_counter += 1;
}
/// Runs the msize opcode for the interpreter.
/// 0x59 -> MSIZE
pub fn msizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.memory.getCurrentMemorySize());

    self.program_counter += 1;
}
/// Runs the mstore opcode for the interpreter.
/// 0x52 -> MSTORE
pub fn mstoreInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const value = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (offset > comptime std.math.maxInt(u64))
        return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size: u64 = @truncate(offset + 32);
    try self.resize(new_size);

    try self.memory.writeInt(offset, value);
    self.program_counter += 1;
}
/// Runs the mstore8 opcode for the interpreter.
/// 0x53 -> MSTORE8
pub fn mstore8Instruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const value = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (offset > comptime std.math.maxInt(u64))
        return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size: u64 = @truncate(offset + 1);
    try self.resize(new_size);

    try self.memory.writeByte(offset, @truncate(value));
    self.program_counter += 1;
}
