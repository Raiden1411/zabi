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
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const destination = try self.stack.tryPopUnsafe();
    const source = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

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
/// Runs the mload opcode for the interpreter.
/// 0x51 -> MLOAD
pub fn mloadInstruction(self: *Interpreter) MemoryInstructionErrors!void {
    const offset = try self.stack.tryPeek();

    const as_usize = std.math.cast(usize, offset.*) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
    const new_size = as_usize +| 32;
    try self.resize(new_size);

    offset.* = self.memory.wordToInt(as_usize);
}
/// Runs the msize opcode for the interpreter.
/// 0x59 -> MSIZE
pub fn msizeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    try self.stack.pushUnsafe(self.memory.getCurrentMemorySize());
}
/// Runs the mstore opcode for the interpreter.
/// 0x52 -> MSTORE
pub fn mstoreInstruction(self: *Interpreter) MemoryInstructionErrors!void {
    const offset = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
    const new_size = as_usize +| 32;
    try self.resize(new_size);

    self.memory.writeInt(as_usize, value);
}
/// Runs the mstore8 opcode for the interpreter.
/// 0x53 -> MSTORE8
pub fn mstore8Instruction(self: *Interpreter) MemoryInstructionErrors!void {
    const offset = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
    const new_size = as_usize +| 1;
    try self.resize(new_size);

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, value, .little);

    self.memory.writeByte(as_usize, buffer[0]);
}
