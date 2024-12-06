const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Contract = evm.contract.Contract;
const Interpreter = evm.Interpreter;
const Memory = evm.memory.Memory;

test "Address" {
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.addressInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Caller" {
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.callerInstruction(&interpreter);

    try testing.expectEqual(@as(u160, @bitCast([_]u8{1} ** 20)), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Value" {
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.callValueInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CodeSize" {
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.codeSizeInstruction(&interpreter);

    try testing.expectEqual(33, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CallDataSize" {
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.callDataSizeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Gas" {
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

    interpreter.gas_tracker = gas.GasTracker.init(1000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    try evm.instructions.system.gasInstruction(&interpreter);

    try testing.expectEqual(998, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "ReturnDataSize" {
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
    interpreter.contract = contract;
    interpreter.return_data = &.{};
    interpreter.spec = .LATEST;

    try evm.instructions.system.returnDataSizeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CallDataLoad" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
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
    interpreter.contract = contract;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.system.callDataLoadInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(33);
        try evm.instructions.system.callDataLoadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}

test "CallDataCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.system.callDataCopyInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(64);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.system.callDataCopyInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.memory.wordToInt(0));
        try testing.expectEqual(15, interpreter.gas_tracker.used_amount);
    }
}

test "CodeCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &data },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);

    try evm.instructions.system.codeCopyInstruction(&interpreter);

    try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
    try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
}

test "Keccak256" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    {
        try interpreter.memory.resize(32);
        interpreter.memory.writeInt(0, 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000);

        try interpreter.stack.pushUnsafe(4);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.system.keccakInstruction(&interpreter);

        try testing.expectEqual(0x29045a592007d0c246ef02c2223570da9522d0cf0f73282c79a1bc8f0bb2c238, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(36, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.system.keccakInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(66, interpreter.gas_tracker.used_amount);
    }
}

test "ReturnDataCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &data;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.system.returnDataCopyInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
}
