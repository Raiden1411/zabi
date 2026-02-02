const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Contract = evm.contract.Contract;
const GasTracker = gas.GasTracker;
const Interpreter = evm.Interpreter;
const Memory = evm.memory.Memory;
const PlainHost = evm.host.PlainHost;

test "Program counter" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    try evm.instructions.control.programCounterInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    // JUMPDEST, STOP
    var code = [_]u8{ 0x5b, 0x00 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .return_action);
    try testing.expectEqual(.stopped, result.return_action.result);
    try testing.expectEqual(1, result.return_action.gas.usedAmount());
}

test "Jump" {
    // PUSH1 4, JUMP, REVERT, JUMPDEST, STOP
    var code = [_]u8{ 0x60, 0x04, 0x56, 0xfd, 0x5b, 0x00 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .return_action);
    try testing.expectEqual(.stopped, result.return_action.result);
    // PUSH1 (3) + JUMP (8) + JUMPDEST (1) = 12
    try testing.expectEqual(12, result.return_action.gas.usedAmount());
}

test "Jump invalid" {
    // PUSH1 3 (invalid target), JUMP, REVERT, JUMPDEST
    var code = [_]u8{ 0x60, 0x03, 0x56, 0xfd, 0x5b };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    try testing.expectError(error.InvalidJump, interpreter.run());
}

test "Conditional Jump taken" {
    // PUSH1 1, PUSH1 6, JUMPI, REVERT, JUMPDEST, STOP
    var code = [_]u8{ 0x60, 0x01, 0x60, 0x06, 0x57, 0xfd, 0x5b, 0x00 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .return_action);
    try testing.expectEqual(.stopped, result.return_action.result);
    // PUSH1 (3) + PUSH1 (3) + JUMPI (8) + JUMPDEST (1) = 15
    try testing.expectEqual(15, result.return_action.gas.usedAmount());
}

test "Conditional Jump not taken" {
    // PUSH1 0, PUSH1 6, JUMPI, PUSH1 42, STOP
    var code = [_]u8{ 0x60, 0x00, 0x60, 0x06, 0x57, 0x60, 0x2a, 0x00 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .return_action);
    try testing.expectEqual(.stopped, result.return_action.result);
    // PUSH1 (3) + PUSH1 (3) + JUMPI (8) + PUSH1 (3) = 17
    try testing.expectEqual(17, result.return_action.gas.usedAmount());
    try testing.expectEqual(42, try interpreter.stack.tryPopUnsafe());
}

test "Conditional Jump invalid" {
    // PUSH1 1, PUSH1 5, JUMPI, REVERT, JUMPDEST
    var code = [_]u8{ 0x60, 0x01, 0x60, 0x05, 0x57, 0xfd, 0x5b };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &code },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(testing.allocator);

    var plain: PlainHost = undefined;
    defer plain.deinit();
    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{});
    try testing.expectError(error.InvalidJump, interpreter.run());
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
        try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
}
