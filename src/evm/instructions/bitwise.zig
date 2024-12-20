const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../Interpreter.zig");

/// Performs and instruction for the interpreter.
/// AND -> 0x15
pub fn andInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = first & second.*;
}
/// Performs byte instruction for the interpreter.
/// AND -> 0x1A
pub fn byteInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    if (first >= 32) {
        second.* = 0;

        return;
    }

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, second.*, .big);

    second.* = buffer[@intCast(first)];
}
/// Performs equal instruction for the interpreter.
/// EQ -> 0x14
pub fn equalInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = @intFromBool(first == second.*);
}
/// Performs equal instruction for the interpreter.
/// GT -> 0x11
pub fn greaterThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = @intFromBool(first > second.*);
}
/// Performs iszero instruction for the interpreter.
/// ISZERO -> 0x15
pub fn isZeroInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPeek();
    first.* = @intFromBool(first.* == 0);
}
/// Performs LT instruction for the interpreter.
/// LT -> 0x10
pub fn lowerThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = @intFromBool(first < second.*);
}
/// Performs NOT instruction for the interpreter.
/// NOT -> 0x19
pub fn notInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPeek();
    first.* = ~first.*;
}
/// Performs OR instruction for the interpreter.
/// OR -> 0x17
pub fn orInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = first | second.*;
}
/// Performs shl instruction for the interpreter.
/// SHL -> 0x1B
pub fn shiftLeftInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const shift = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPeek();

    value.* = std.math.shl(u256, value.*, shift);
}
/// Performs shr instruction for the interpreter.
/// SHR -> 0x1C
pub fn shiftRightInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const shift = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPeek();

    value.* = std.math.shr(u256, value.*, shift);
}
/// Performs SGT instruction for the interpreter.
/// SGT -> 0x12
pub fn signedGreaterThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second.*);

    second.* = @intFromBool(casted_first > casted_second);
}
/// Performs SLT instruction for the interpreter.
/// SLT -> 0x12
pub fn signedLowerThanInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second.*);

    second.* = @intFromBool(casted_first < casted_second);
}
/// Performs SAR instruction for the interpreter.
/// SAR -> 0x1D
pub fn signedShiftRightInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const shift: usize = std.math.cast(usize, first) orelse return error.Overflow;

    if (shift >= 256) {
        const mask = 1 << 255;

        if ((mask & second.*) != 0) {
            second.* = std.math.maxInt(u256);
        } else {
            second.* = 0;
        }
    } else {
        const mask = 1 << 255;

        if ((mask & second.*) != 0) {
            const shifted = second.* >> @as(u8, @intCast(shift));
            const mask_value = std.math.shl(u256, std.math.maxInt(u256), 256 - shift);

            second.* = shifted | mask_value;
        } else {
            second.* = second.* >> @as(u8, @intCast(shift));
        }
    }
}
/// Performs XOR instruction for the interpreter.
/// XOR -> 0x18
pub fn xorInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = first ^ second.*;
}
