const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Interpreter = evm.Interpreter;

test "And" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.andInstruction(&interpreter);

    try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Or" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.orInstruction(&interpreter);

    try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Xor" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.xorInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Greater than" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.greaterThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(false), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Lower than" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.lowerThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(false), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Equal" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0x7f);
    try interpreter.stack.pushUnsafe(0x7f);

    try evm.instructions.bitwise.equalInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "IsZero" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0);

    try evm.instructions.bitwise.isZeroInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Signed Greater than" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(std.math.maxInt(u256) - 1);
    try interpreter.stack.pushUnsafe(std.math.maxInt(u256));

    try evm.instructions.bitwise.signedGreaterThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Signed Lower than" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
    try interpreter.stack.pushUnsafe(std.math.maxInt(u256) - 1);

    try evm.instructions.bitwise.signedLowerThanInstruction(&interpreter);

    try testing.expectEqual(@intFromBool(true), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Shift Left" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(2);
    try interpreter.stack.pushUnsafe(1);

    try evm.instructions.bitwise.shiftLeftInstruction(&interpreter);

    try testing.expectEqual(4, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
}

test "Shift Right" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(2);
    try interpreter.stack.pushUnsafe(1);

    try evm.instructions.bitwise.shiftRightInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
}

test "SAR" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0);
        try interpreter.stack.pushUnsafe(4);

        try evm.instructions.bitwise.signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try evm.instructions.bitwise.signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.usedAmount());
    }
}

test "Not" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try interpreter.stack.pushUnsafe(0);

    try evm.instructions.bitwise.notInstruction(&interpreter);

    try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}

test "Byte" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(0x1F);

        try evm.instructions.bitwise.byteInstruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0xFF00);
        try interpreter.stack.pushUnsafe(0x1E);

        try evm.instructions.bitwise.byteInstruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0xFFFE);
        try interpreter.stack.pushUnsafe(0x1F);

        try evm.instructions.bitwise.byteInstruction(&interpreter);

        try testing.expectEqual(0xFE, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(9, interpreter.gas_tracker.usedAmount());
    }
}
