const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const utils = @import("zabi-utils").utils;

const Interpreter = @import("../Interpreter.zig");
const Memory = @import("../memory.zig").Memory;

pub const MemoryInstructionErrors = Interpreter.InstructionErrors || Memory.Error || error{Overflow};

/// Runs the mcopy opcode for the interpreter.
/// 0x5E -> MCOPY
pub fn mcopyInstruction(self: *Interpreter) (MemoryInstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.CANCUN)) {
        @branchHint(.cold);
        return error.InstructionNotEnabled;
    }

    const destination = self.stack.pop();
    const source = self.stack.pop();
    const length = self.stack.pop();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.OutOfGas);

    if (len == 0)
        return;

    const source_usize = std.math.cast(usize, source) orelse return error.Overflow;
    const destination_usize = std.math.cast(usize, destination) orelse return error.Overflow;

    const new_size = @max(destination_usize, source_usize) +| len;
    try self.resize(new_size);

    self.memory.memoryCopy(destination_usize, source_usize, len);
}
