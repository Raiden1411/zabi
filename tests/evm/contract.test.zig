const actions = evm.actions;
const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const CallAction = actions.CallAction;
const Contract = @import("zabi").evm.contract.Contract;
const CreateScheme = actions.CreateScheme;
const Interpreter = evm.Interpreter;
const Memory = evm.memory.Memory;
const PlainHost = evm.host.PlainHost;

test "Create" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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
    interpreter.allocator = testing.allocator;
    interpreter.contract = &contract;

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.contract.createInstruction(&interpreter, false);

        try testing.expect(interpreter.next_action == .create_action);
        defer testing.allocator.free(interpreter.next_action.create_action.init_code);

        try testing.expectEqual(29531750, interpreter.gas_tracker.usedAmount());
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.contract.createInstruction(&interpreter, false);

        try testing.expect(interpreter.next_action == .create_action);
        defer testing.allocator.free(interpreter.next_action.create_action.init_code);

        try testing.expectEqual(30_000_000, interpreter.gas_tracker.usedAmount());
    }
}

test "Create2" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.allocator = testing.allocator;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = host.host();
    interpreter.contract = &contract;

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.contract.createInstruction(&interpreter, true);

        try testing.expect(interpreter.next_action == .create_action);
        try testing.expect(interpreter.next_action.create_action.scheme == .create2);
        defer testing.allocator.free(interpreter.next_action.create_action.init_code);

        try testing.expectEqual(29531750, interpreter.gas_tracker.usedAmount());
    }
    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.contract.createInstruction(&interpreter, true));
    }
}

test "Call" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.allocator = testing.allocator;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = host.host();
    interpreter.spec = .LATEST;
    interpreter.contract = &contract;

    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.callInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .call);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(65635, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.callInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .call);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(131273, interpreter.gas_tracker.usedAmount());
    }
    {
        interpreter.is_static = true;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.callInstruction(&interpreter);

        try testing.expect(interpreter.status == .call_with_value_not_allowed_in_static_call);
    }
}

test "CallCode" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.allocator = testing.allocator;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = host.host();
    interpreter.spec = .LATEST;
    interpreter.contract = &contract;

    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.callCodeInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .callcode);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(65635, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.callCodeInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .callcode);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(131273, interpreter.gas_tracker.usedAmount());
    }
}

test "DelegateCall" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.allocator = testing.allocator;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = host.host();
    interpreter.contract = &contract;

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.delegateCallInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .delegate);
        try testing.expect(interpreter.next_action.call_action.value == .limbo);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(65635, interpreter.gas_tracker.usedAmount());
    }
    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.contract.delegateCallInstruction(&interpreter));
    }
}

test "StaticCall" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.allocator = testing.allocator;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = host.host();
    interpreter.contract = &contract;

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0xFFFF);

        try evm.instructions.contract.staticCallInstruction(&interpreter);

        try testing.expect(interpreter.next_action == .call_action);
        try testing.expect(interpreter.status == .call_or_create);
        try testing.expect(interpreter.next_action.call_action.scheme == .static);
        defer testing.allocator.free(interpreter.next_action.call_action.inputs);

        try testing.expectEqual(65635, interpreter.gas_tracker.usedAmount());
    }
    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.contract.staticCallInstruction(&interpreter));
    }
}
