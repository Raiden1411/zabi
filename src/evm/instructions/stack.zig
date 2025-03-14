const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Interpreter = @import("../Interpreter.zig");

/// Runs the swap instructions opcodes for the interpreter.
/// 0x80 .. 0x8F -> DUP1 .. DUP16
pub fn dupInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
    try self.stack.dupUnsafe(position);
}
/// Runs the pop opcode for the interpreter.
/// 0x50 -> POP
pub fn popInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    _ = try self.stack.tryPopUnsafe();
}
/// Runs the push instructions opcodes for the interpreter.
/// 0x60 .. 0x7F -> PUSH1 .. PUSH32
pub fn pushInstruction(self: *Interpreter, comptime size: u8) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    comptime std.debug.assert(size <= 32); // Size higher than expected.
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    std.debug.assert(self.code.len >= self.program_counter + size);
    const slice: [size]u8 = self.code[self.program_counter + 1 .. self.program_counter + 1 + size][0..size].*;

    const IntType = std.meta.Int(.unsigned, @as(u16, @intCast(size)) * 8);
    try self.stack.pushUnsafe(std.mem.readInt(IntType, &slice, .big));

    self.program_counter += size;
}
/// Runs the push0 opcode for the interpreter.
/// 0x5F -> PUSH0
pub fn pushZeroInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.SHANGHAI))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    try self.stack.pushUnsafe(0);
}
/// Runs the swap instructions opcodes for the interpreter.
/// 0x90 .. 0x9F -> SWAP1 .. SWAP16
pub fn swapInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
    try self.stack.swapToTopUnsafe(position);
}
