const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Contract = evm.contract.Contract;
const GasTracker = gas.GasTracker;
const Interpreter = evm.Interpreter;
const Memory = evm.memory.Memory;

test "Program counter" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.programCounterInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Unknown" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.unknownInstruction(&interpreter);

    try testing.expectEqual(.opcode_not_found, interpreter.status);
}

test "Invalid" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.invalidInstruction(&interpreter);

    try testing.expectEqual(.invalid, interpreter.status);
}

test "Stopped" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.stopInstruction(&interpreter);

    try testing.expectEqual(.stopped, interpreter.status);
}

test "Jumpdest" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.jumpDestInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.gas_tracker.used_amount);
}

test "Jump" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{0} ** 31 ++ [_]u8{0x5b}) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = &contract;

    {
        try interpreter.stack.pushUnsafe(31);
        try evm.instructions.control.jumpInstruction(&interpreter);

        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(30, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(30);
        try evm.instructions.control.jumpInstruction(&interpreter);

        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(30, interpreter.program_counter);
        try testing.expectEqual(.invalid_jump, interpreter.status);
    }
}

test "Conditional Jump" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{0} ** 31 ++ [_]u8{0x5b}) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = &contract;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(31);
        try evm.instructions.control.conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(30, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(30);
        try evm.instructions.control.conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(30, interpreter.program_counter);
        try testing.expectEqual(.invalid_jump, interpreter.status);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(30);
        try evm.instructions.control.conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(24, interpreter.gas_tracker.used_amount);
    }
}

test "Reverted" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
        testing.allocator.free(interpreter.return_data);
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &.{};
    interpreter.allocator = testing.allocator;

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.control.revertInstruction(&interpreter);

        try testing.expectEqual(.reverted, interpreter.status);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.control.revertInstruction(&interpreter));
    }
}

test "Return" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
        testing.allocator.free(interpreter.return_data);
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &.{};
    interpreter.allocator = testing.allocator;

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);
    try evm.instructions.control.returnInstruction(&interpreter);

    try testing.expectEqual(.returned, interpreter.status);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}
