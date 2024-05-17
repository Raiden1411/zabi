const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../interpreter.zig");

/// Performs and instruction for the interpreter.
/// AND -> 0x15
pub fn andInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(first & second);
    self.program_counter += 1;
}
/// Performs byte instruction for the interpreter.
/// AND -> 0x1A
fn byteInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (first >= 32) {
        try self.stack.pushUnsafe(0);
        self.program_counter += 1;

        return;
    }

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, second, .little);

    try self.stack.pushUnsafe(buffer[first..][first - 1]);
    self.program_counter += 1;
}
/// Performs equal instruction for the interpreter.
/// EQ -> 0x14
fn equalInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(@intFromBool(first == second));
    self.program_counter += 1;
}
/// Performs equal instruction for the interpreter.
/// GT -> 0x11
fn greaterThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(@intFromBool(first > second));
    self.program_counter += 1;
}
/// Performs iszero instruction for the interpreter.
/// ISZERO -> 0x15
fn isZeroInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(@intFromBool(first == 0));
    self.program_counter += 1;
}
/// Performs LT instruction for the interpreter.
/// LT -> 0x10
pub fn lowerThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(@intFromBool(first < second));
    self.program_counter += 1;
}
/// Performs NOT instruction for the interpreter.
/// NOT -> 0x19
fn notInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(~first);
    self.program_counter += 1;
}
/// Performs OR instruction for the interpreter.
/// OR -> 0x17
fn orInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(first | second);
    self.program_counter += 1;
}
/// Performs shl instruction for the interpreter.
/// SHL -> 0x1B
fn shiftLeftInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const shift = first << second;

    try self.stack.pushUnsafe(shift);
    self.program_counter += 1;
}
/// Performs shr instruction for the interpreter.
/// SHR -> 0x1C
fn shiftRightInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const shift = first >> second;

    try self.stack.pushUnsafe(shift);
    self.program_counter += 1;
}
/// Performs SGT instruction for the interpreter.
/// SGT -> 0x12
fn signedGreaterThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    try self.stack.pushUnsafe(@intFromBool(casted_first > casted_second));
    self.program_counter += 1;
}
/// Performs SLT instruction for the interpreter.
/// SLT -> 0x12
fn signedLowerThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    try self.stack.pushUnsafe(@intFromBool(casted_first < casted_second));
    self.program_counter += 1;
}
/// Performs SAR instruction for the interpreter.
/// SAR -> 0x1D
fn signedShiftRightInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    const shift = casted_first >> casted_second;

    try self.stack.pushUnsafe(shift);
    self.program_counter += 1;
}
/// Performs XOR instruction for the interpreter.
/// XOR -> 0x18
fn xorInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(first ^ second);
    self.program_counter += 1;
}
