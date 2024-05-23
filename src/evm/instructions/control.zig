const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../interpreter.zig");

/// Runs the jumpi instruction opcode for the interpreter.
/// 0x57 -> JUMPI
pub fn conditionalJumpInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const target = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const condition = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < target)
        return error.InvalidJump;

    if (condition != 0) {
        if (!self.contract.isValidJump(@intCast(target))) {
            self.status = .invalid_jump;
            return;
        }

        self.program_counter += @intCast(target);
    }
}
/// Runs the pc instruction opcode for the interpreter.
/// 0x58 -> PC
pub fn programCounterInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.program_counter);
    self.program_counter += 1;
}
/// Runs the jump instruction opcode for the interpreter.
/// 0x56 -> JUMP
pub fn jumpInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);
    const target = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < target)
        return error.InvalidJump;

    if (!self.contract.isValidJump(@intCast(target))) {
        self.status = .invalid_jump;
        return;
    }

    self.program_counter += @intCast(target);
}
/// Runs the jumpdest instruction opcode for the interpreter.
/// 0x5B -> JUMPDEST
pub fn jumpDestInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.JUMPDEST);
    self.program_counter += 1;
}
/// Runs the invalid instruction opcode for the interpreter.
/// 0xFE -> INVALID
pub fn invalidInstruction(self: *Interpreter) void {
    self.status = .invalid;
}
/// Runs the stop instruction opcode for the interpreter.
/// 0x00 -> STOP
pub fn stopInstruction(self: *Interpreter) void {
    self.status = .stopped;
}
/// Runs the return instruction opcode for the interpreter.
/// 0xF3 -> RETURN
pub fn returnInstruction(self: *Interpreter) !void {
    return returnAction(self, .returned);
}
/// Runs the rever instruction opcode for the interpreter.
/// 0xFD -> REVERT
pub fn revertInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    return returnAction(self, .reverted);
}
/// Runs the stop instruction opcode for the interpreter.
/// 0x00 -> STOP
pub fn unknowInstruction(self: *Interpreter) void {
    self.status = .opcode_not_found;
}

// Internal action for return type instructions.
fn returnAction(self: *Interpreter, status: Interpreter.InterpreterStatus) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < length)
        return error.Overflow;

    if (length != 0) {
        if (comptime std.math.maxInt(u64) < offset)
            return error.Overflow;

        const return_buffer = try self.allocator.alloc(u8, length);

        try self.resize(@truncate(offset + length));
        const slice = self.memory.getSlice();
        @memcpy(return_buffer, slice[offset .. offset + length]);
        self.return_data = return_buffer;
    }
    self.status = status;
}
