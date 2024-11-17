const evm = @import("zabi").evm;
const gas = evm.gas;
const host = evm.host;
const std = @import("std");
const testing = std.testing;

const Interpreter = evm.Interpreter;
const PlainHost = host.PlainHost;
const Memory = evm.memory.Memory;

test "Balance" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try evm.instructions.host.balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try evm.instructions.host.balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try evm.instructions.host.balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1200, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try evm.instructions.host.balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1220, interpreter.gas_tracker.used_amount);
    }
}

test "BlockHash" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    try interpreter.stack.pushUnsafe(0);
    try evm.instructions.host.blockHashInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(20, interpreter.gas_tracker.used_amount);
}

test "ExtCodeCopy" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);

    try evm.instructions.host.extCodeCopyInstruction(&interpreter);

    try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
}

test "ExtCodeHash" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1200, interpreter.gas_tracker.used_amount);
    }
}

test "ExtCodeSize" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(820, interpreter.gas_tracker.used_amount);
    }
}

test "Log" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = plain.host();
    interpreter.allocator = testing.allocator;

    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.logInstruction(&interpreter, 0);

        try testing.expectEqual(375, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.logInstruction(&interpreter, 1);

        try testing.expectEqual(1384, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.logInstruction(&interpreter, 2);

        try testing.expectEqual(2509, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.host.logInstruction(&interpreter, 3);

        try testing.expectEqual(4017, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(3);
        try evm.instructions.host.logInstruction(&interpreter, 4);

        try testing.expectEqual(5908, interpreter.gas_tracker.used_amount);
    }
}

test "SelfBalance" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    interpreter.spec = .LATEST;
    try evm.instructions.host.selfBalanceInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.used_amount);

    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.host.selfBalanceInstruction(&interpreter));
    }
}

test "Sload" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2600, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3400, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3600, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3650, interpreter.gas_tracker.used_amount);
    }
}

test "Sstore" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.sstoreInstruction(&interpreter);

        try testing.expectEqual(2200, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.sstoreInstruction(&interpreter);

        try testing.expectEqual(2300, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.sstoreInstruction(&interpreter);

        try testing.expectEqual(7300, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.sstoreInstruction(&interpreter);

        try testing.expectEqual(12300, interpreter.gas_tracker.used_amount);
    }
}

test "Tload" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.host.tloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.host.tloadInstruction(&interpreter));
    }
}

test "Tstore" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try evm.instructions.host.tstoreInstruction(&interpreter);

        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.host.tstoreInstruction(&interpreter));
    }
}
