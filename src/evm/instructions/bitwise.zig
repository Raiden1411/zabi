const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Interpreter = @import("../Interpreter.zig");
const Stack = @import("../../utils/stack.zig").Stack;

/// Performs and instruction for the interpreter.
/// AND -> 0x15
pub fn andInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(first & second);
}
/// Performs byte instruction for the interpreter.
/// AND -> 0x1A
pub fn byteInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    if (first >= 32) {
        try self.stack.pushUnsafe(0);

        return;
    }

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, second, .big);

    try self.stack.pushUnsafe(buffer[@intCast(first)]);
}
/// Performs equal instruction for the interpreter.
/// EQ -> 0x14
pub fn equalInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(@intFromBool(first == second));
}
/// Performs equal instruction for the interpreter.
/// GT -> 0x11
pub fn greaterThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(@intFromBool(first > second));
}
/// Performs iszero instruction for the interpreter.
/// ISZERO -> 0x15
pub fn isZeroInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(@intFromBool(first == 0));
}
/// Performs LT instruction for the interpreter.
/// LT -> 0x10
pub fn lowerThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(@intFromBool(first < second));
}
/// Performs NOT instruction for the interpreter.
/// NOT -> 0x19
pub fn notInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(~first);
}
/// Performs OR instruction for the interpreter.
/// OR -> 0x17
pub fn orInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(first | second);
}
/// Performs shl instruction for the interpreter.
/// SHL -> 0x1B
pub fn shiftLeftInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const shift = std.math.shl(u256, first, second);

    try self.stack.pushUnsafe(shift);
}
/// Performs shr instruction for the interpreter.
/// SHR -> 0x1C
pub fn shiftRightInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const shift = std.math.shr(u256, first, second);

    try self.stack.pushUnsafe(shift);
}
/// Performs SGT instruction for the interpreter.
/// SGT -> 0x12
pub fn signedGreaterThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    try self.stack.pushUnsafe(@intFromBool(casted_first > casted_second));
}
/// Performs SLT instruction for the interpreter.
/// SLT -> 0x12
pub fn signedLowerThanInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    try self.stack.pushUnsafe(@intFromBool(casted_first < casted_second));
}
/// Performs SAR instruction for the interpreter.
/// SAR -> 0x1D
pub fn signedShiftRightInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    const shift: usize = @truncate(first);

    if (shift >= 256) {
        const mask = 1 << 255;

        if ((mask & second) != 0) {
            try self.stack.pushUnsafe(std.math.maxInt(u256));
        } else {
            try self.stack.pushUnsafe(0);
        }
    } else {
        const mask = 1 << 255;

        if ((mask & second) != 0) {
            const shifted = second >> @as(u8, @intCast(shift));
            const mask_value = std.math.shl(u256, std.math.maxInt(u256), 256 - shift);

            try self.stack.pushUnsafe(shifted | mask_value);
        } else {
            try self.stack.pushUnsafe(second >> @as(u8, @intCast(shift)));
        }
    }
}
/// Performs XOR instruction for the interpreter.
/// XOR -> 0x18
pub fn xorInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();

    try self.stack.pushUnsafe(first ^ second);
}

test "And" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try andInstruction(&interpreter);

    try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Or" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try orInstruction(&interpreter);

    try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Xor" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try xorInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Greater than" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try greaterThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(false), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Lower than" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try lowerThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(false), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Equal" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try equalInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "IsZero" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0);

    try isZeroInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Signed Greater than" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(std.math.maxInt(u256) - 1);
    try interpreter.stack.pushUnsafe(std.math.maxInt(u256));

    try signedGreaterThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Signed Lower than" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
    try interpreter.stack.pushUnsafe(std.math.maxInt(u256) - 1);

    try signedLowerThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Shift Left" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(2);
    try interpreter.stack.pushUnsafe(1);

    try shiftLeftInstruction(&interpreter);

    try testing.expectEqual(4, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
}

test "Shift Right" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(1);
    try interpreter.stack.pushUnsafe(2);

    try shiftRightInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
}

test "SAR" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0);
        try interpreter.stack.pushUnsafe(4);

        try signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}

test "Not" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0);

    try notInstruction(&interpreter);

    try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}

test "Byte" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(0x1F);

        try byteInstruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0xFF00);
        try interpreter.stack.pushUnsafe(0x1E);

        try byteInstruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0xFFFE);
        try interpreter.stack.pushUnsafe(0x1F);

        try byteInstruction(&interpreter);

        try testing.expectEqual(0xFE, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
}
