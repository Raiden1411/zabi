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

test "Push" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        interpreter.code = @constCast(&[_]u8{ 0x60, 0xFF });
        try pushInstruction(&interpreter, 1);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x7F} ++ &[_]u8{0xFF} ** 32);
        try pushInstruction(&interpreter, 32);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(32, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x73} ++ &[_]u8{0xFF} ** 20);
        try pushInstruction(&interpreter, 20);

        try testing.expectEqual(std.math.maxInt(u160), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(20, interpreter.program_counter);
    }
}

test "Push Zero" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        interpreter.spec = .LATEST;

        try pushZeroInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, pushZeroInstruction(&interpreter));
    }
}

test "Dup" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(69);

        try dupInstruction(&interpreter, 1);

        try testing.expectEqual(69, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
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
    }
}

test "Swap" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(420);
        try interpreter.stack.pushUnsafe(69);

        try swapInstruction(&interpreter, 1);

        try testing.expectEqual(420, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(69);

        try swapInstruction(&interpreter, 5);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}

test "Pop" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try pushZeroInstruction(&interpreter);
    try popInstruction(&interpreter);
}
