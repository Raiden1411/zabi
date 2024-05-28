const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Interpreter = @import("../interpreter.zig");
const Stack = @import("../../utils/stack.zig").Stack;

/// Runs the swap instructions opcodes for the interpreter.
/// 0x80 .. 0x8F -> DUP1 .. DUP16
pub fn dupInstruction(self: *Interpreter, position: u8) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    try self.stack.dupUnsafe(position);
    self.program_counter += 1;
}
/// Runs the pop opcode for the interpreter.
/// 0x50 -> POP
pub fn popInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    _ = self.stack.popUnsafe() orelse return error.StackUnderflow;
}
/// Runs the push instructions opcodes for the interpreter.
/// 0x60 .. 0x7F -> PUSH1 .. PUSH32
pub fn pushInstruction(self: *Interpreter, size: u8) !void {
    if (!self.spec.enabled(.SHANGHAI))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    std.debug.assert(size <= 32); // Size higher than expected.

    // Advance the counter by one so that get the data that we want
    self.program_counter += 1;
    const slice = self.code[self.program_counter .. self.program_counter + size];

    var buffer: [32]u8 = [_]u8{0} ** 32;
    @memcpy(buffer[0..size], slice[0..]);
    try self.stack.pushUnsafe(@bitCast(buffer));

    self.program_counter += size;
}
/// Runs the push0 opcode for the interpreter.
/// 0x5F -> PUSH0
pub fn pushZeroInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.SHANGHAI))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(0);
    self.program_counter += 1;
}
/// Runs the swap instructions opcodes for the interpreter.
/// 0x90 .. 0x9F -> SWAP1 .. SWAP16
pub fn swapInstruction(self: *Interpreter, position: u8) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    try self.stack.swapToTopUnsafe(position);
    self.program_counter += 1;
}

test "Push" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        interpreter.code = @constCast(&[_]u8{ 0x60, 0xFF });
        try pushInstruction(&interpreter, 1);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x7F} ++ &[_]u8{0xFF} ** 32);
        try pushInstruction(&interpreter, 32);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(33, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x73} ++ &[_]u8{0xFF} ** 20);
        try pushInstruction(&interpreter, 20);

        try testing.expectEqual(std.math.maxInt(u160), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(21, interpreter.program_counter);
    }
}

test "Push Zero" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        interpreter.spec = .LATEST;

        try pushZeroInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, pushZeroInstruction(&interpreter));
    }
}

test "Dup" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(69);

        try dupInstruction(&interpreter, 1);

        try testing.expectEqual(69, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);

        try dupInstruction(&interpreter, 6);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Swap" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(420);
        try interpreter.stack.pushUnsafe(69);

        try swapInstruction(&interpreter, 1);

        try testing.expectEqual(69, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);

        try swapInstruction(&interpreter, 6);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Pop" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try pushZeroInstruction(&interpreter);
    try popInstruction(&interpreter);
}
