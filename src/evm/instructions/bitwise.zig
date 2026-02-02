const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../Interpreter.zig");

/// Performs SAR instruction for the interpreter.
/// SAR -> 0x1D
pub fn signedShiftRightInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = self.stack.pop();
    const second = self.stack.peek();

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
