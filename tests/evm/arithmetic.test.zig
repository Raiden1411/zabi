const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Interpreter = evm.Interpreter;

test "Addition" {
    var interpreter: Interpreter = undefined;
    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.addInstruction(&interpreter);
        try testing.expectEqual(3, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.addInstruction(&interpreter);
        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}
test "Multiplication" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.mulInstruction(&interpreter);
        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.mulInstruction(&interpreter);
        try testing.expectEqual(std.math.maxInt(u256) - 1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}
test "Subtraction" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.subInstruction(&interpreter);
        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.subInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}
test "Division" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.divInstruction(&interpreter);
        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.divInstruction(&interpreter);
        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}
test "Signed Division" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try evm.instructions.arithmetic.signedDivInstruction(&interpreter);
        try testing.expectEqual(0, @as(i256, @bitCast(interpreter.stack.popUnsafe().?)));
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.divInstruction(&interpreter);
        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}
test "Mod" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.modInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.modInstruction(&interpreter);
        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}
test "Signed Mod" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try evm.instructions.arithmetic.signedModInstruction(&interpreter);
        try testing.expectEqual(-1, @as(i256, @bitCast(interpreter.stack.popUnsafe().?)));
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.signedModInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
}
test "Addition and Mod" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.modAdditionInstruction(&interpreter);
        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.modAdditionInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
    }
}
test "Multiplication and Mod" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.modMultiplicationInstruction(&interpreter);
        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(4);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.modMultiplicationInstruction(&interpreter);
        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
    }
}
test "Exponent" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.exponentInstruction(&interpreter);
        try testing.expectEqual(4, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(60, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u16));
        try evm.instructions.arithmetic.exponentInstruction(&interpreter);
        try testing.expectEqual(std.math.maxInt(u16), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(120, interpreter.gas_tracker.used_amount);
    }
}
test "Sign Extend" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;
    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.arithmetic.signExtendInstruction(&interpreter);
        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.arithmetic.signExtendInstruction(&interpreter);
        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0xFF);
        try evm.instructions.arithmetic.signExtendInstruction(&interpreter);
        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(15, interpreter.gas_tracker.used_amount);
    }
}
