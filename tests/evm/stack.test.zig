const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Interpreter = evm.Interpreter;

test "Push" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        interpreter.code = @constCast(&[_]u8{ 0x60, 0xFF });
        try evm.instructions.stack.pushInstruction(&interpreter, 1);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x7F} ++ &[_]u8{0xFF} ** 32);
        try evm.instructions.stack.pushInstruction(&interpreter, 32);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(32, interpreter.program_counter);
    }
    {
        interpreter.program_counter = 0;
        interpreter.code = @constCast(&[_]u8{0x73} ++ &[_]u8{0xFF} ** 20);
        try evm.instructions.stack.pushInstruction(&interpreter, 20);

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

        try evm.instructions.stack.pushZeroInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, evm.instructions.stack.pushZeroInstruction(&interpreter));
    }
}

test "Dup" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(69);

        try evm.instructions.stack.dupInstruction(&interpreter, 1);

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

        try evm.instructions.stack.dupInstruction(&interpreter, 6);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}

test "Swap" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(420);
        try interpreter.stack.pushUnsafe(69);

        try evm.instructions.stack.swapInstruction(&interpreter, 1);

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

        try evm.instructions.stack.swapInstruction(&interpreter, 5);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}

test "Pop" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    try evm.instructions.stack.pushZeroInstruction(&interpreter);
    try evm.instructions.stack.popInstruction(&interpreter);
}
