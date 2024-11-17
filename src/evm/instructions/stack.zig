const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Interpreter = @import("../Interpreter.zig");

/// Runs the swap instructions opcodes for the interpreter.
/// 0x80 .. 0x8F -> DUP1 .. DUP16
pub fn dupInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    try self.stack.dupUnsafe(position);
}
/// Runs the pop opcode for the interpreter.
/// 0x50 -> POP
pub fn popInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    _ = try self.stack.tryPopUnsafe();
}
/// Runs the push instructions opcodes for the interpreter.
/// 0x60 .. 0x7F -> PUSH1 .. PUSH32
pub fn pushInstruction(self: *Interpreter, size: u8) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.SHANGHAI))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    std.debug.assert(size <= 32); // Size higher than expected.

    const slice = self.code[self.program_counter + 1 .. self.program_counter + 1 + size];

    var buffer: [32]u8 = [_]u8{0} ** 32;
    @memcpy(buffer[32 - size ..], slice[0..]);

    try self.stack.pushUnsafe(std.mem.readInt(u256, &buffer, .big));

    self.program_counter += size;
}
/// Runs the push0 opcode for the interpreter.
/// 0x5F -> PUSH0
pub fn pushZeroInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.SHANGHAI))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(0);
}
/// Runs the swap instructions opcodes for the interpreter.
/// 0x90 .. 0x9F -> SWAP1 .. SWAP16
pub fn swapInstruction(self: *Interpreter, position: u8) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    try self.stack.swapToTopUnsafe(position);
}
