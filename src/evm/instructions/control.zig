const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const utils = @import("zabi-utils").utils;

const Contract = @import("../contract.zig").Contract;
const GasTracker = gas.GasTracker;
const Interpreter = @import("../Interpreter.zig");
const Memory = @import("../memory.zig").Memory;

/// Runs the jumpi instruction opcode for the interpreter.
/// 0x57 -> JUMPI
pub fn conditionalJumpInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InvalidJump})!void {
    try self.gas_tracker.updateTracker(constants.MID_STEP);

    const target = try self.stack.tryPopUnsafe();
    const condition = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, target) orelse return error.InvalidJump;

    if (condition != 0) {
        if (!self.contract.isValidJump(as_usize)) {
            @branchHint(.unlikely);
            self.status = .invalid_jump;
            return;
        }

        // Since this runs inside a while loop
        // we decrement it here by once since it will get
        // updated before the next loop starts
        self.program_counter = as_usize - 1;
        return;
    }
}

/// Runs the pc instruction opcode for the interpreter.
/// 0x58 -> PC
pub fn programCounterInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    try self.stack.pushUnsafe(self.program_counter);
}

/// Runs the jump instruction opcode for the interpreter.
/// 0x56 -> JUMP
pub fn jumpInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InvalidJump})!void {
    try self.gas_tracker.updateTracker(constants.MID_STEP);
    const target = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, target) orelse return error.InvalidJump;

    if (!self.contract.isValidJump(as_usize)) {
        @branchHint(.unlikely);
        self.status = .invalid_jump;
        return;
    }

    // Since this runs inside a while loop
    // we decrement it here by once since it will get
    // updated before the next loop starts
    self.program_counter = as_usize - 1;
}

/// Runs the jumpdest instruction opcode for the interpreter.
/// 0x5B -> JUMPDEST
pub fn jumpDestInstruction(self: *Interpreter) GasTracker.Error!void {
    try self.gas_tracker.updateTracker(constants.JUMPDEST);
}

/// Runs the invalid instruction opcode for the interpreter.
/// 0xFE -> INVALID
pub fn invalidInstruction(self: *Interpreter) !void {
    self.status = .invalid;
}

/// Runs the stop instruction opcode for the interpreter.
/// 0x00 -> STOP
pub fn stopInstruction(self: *Interpreter) !void {
    self.status = .stopped;
}

/// Runs the return instruction opcode for the interpreter.
/// 0xF3 -> RETURN
pub fn returnInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    return returnAction(self, .returned);
}

/// Runs the rever instruction opcode for the interpreter.
/// 0xFD -> REVERT
pub fn revertInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{ Overflow, InstructionNotEnabled })!void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    return returnAction(self, .reverted);
}

/// Instructions that gets ran if there is no associated opcode.
pub fn unknownInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    self.status = .opcode_not_found;
}

// Internal action for return type instructions.
fn returnAction(self: *Interpreter, status: Interpreter.InterpreterStatus) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    const offset = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;
    const off = std.math.cast(usize, offset) orelse return error.Overflow;

    if (len != 0) {
        const return_buffer = try self.allocator.alloc(u8, len);

        try self.resize(len +| off);
        const slice = self.memory.getSlice();
        @memcpy(return_buffer, slice[off .. off + len]);
        self.return_data = return_buffer;
    }

    self.status = status;
}
