const evm = @import("zabi").evm;
const gas = evm.gas;
const memory = evm.memory;
const std = @import("std");
const testing = std.testing;

const Interpreter = evm.Interpreter;
const Memory = memory.Memory;

const availableWords = memory.availableWords;

test "Available words" {
    try testing.expectEqual(availableWords(0), 0);
    try testing.expectEqual(availableWords(1), 1);
    try testing.expectEqual(availableWords(31), 1);
    try testing.expectEqual(availableWords(32), 1);
    try testing.expectEqual(availableWords(33), 2);
    try testing.expectEqual(availableWords(63), 2);
    try testing.expectEqual(availableWords(64), 2);
    try testing.expectEqual(availableWords(65), 3);
    try testing.expectEqual(availableWords(std.math.maxInt(u64)), std.math.maxInt(u64) / 32);
}

test "Memory" {
    var mem = try Memory.initWithDefaultCapacity(testing.allocator, null);
    defer mem.deinit();

    try mem.resize(32);
    {
        mem.writeInt(0, 69);
        try testing.expectEqual(69, mem.getMemoryByte(31));
    }
    {
        const int = mem.wordToInt(0);
        try testing.expectEqual(69, int);
    }
    {
        mem.writeWord(0, [_]u8{1} ** 32);
        const int = mem.wordToInt(0);
        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), int);
    }
    {
        mem.writeByte(0, 69);
        const int = mem.getMemoryByte(0);
        try testing.expectEqual(69, int);
    }
}

test "Context" {
    var mem = Memory.initEmpty(testing.allocator, null);
    defer mem.deinit();

    try mem.resize(32);
    try testing.expectEqual(mem.getCurrentMemorySize(), 32);
    try testing.expectEqual(mem.buffer.len, 32);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
    try testing.expectEqual(mem.total_capacity, 60);

    try mem.newContext();
    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 128);
    try testing.expectEqual(mem.checkpoints.items.len, 1);
    try testing.expectEqual(mem.last_checkpoint, 32);
    try testing.expectEqual(mem.total_capacity, 252);

    try mem.newContext();
    try mem.resize(128);
    try testing.expectEqual(mem.getCurrentMemorySize(), 128);
    try testing.expectEqual(mem.buffer.len, 256);
    try testing.expectEqual(mem.checkpoints.items.len, 2);
    try testing.expectEqual(mem.last_checkpoint, 128);
    try testing.expectEqual(mem.total_capacity, 508);

    mem.freeContext();
    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 128);
    try testing.expectEqual(mem.checkpoints.items.len, 1);
    try testing.expectEqual(mem.last_checkpoint, 32);
    try testing.expectEqual(mem.total_capacity, 508);

    mem.freeContext();
    try mem.resize(64);
    try testing.expectEqual(mem.getCurrentMemorySize(), 64);
    try testing.expectEqual(mem.buffer.len, 64);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
    try testing.expectEqual(mem.total_capacity, 508);
}

test "No Context" {
    var mem = Memory.initEmpty(testing.allocator, null);
    defer mem.deinit();

    try mem.resize(32);
    try testing.expectEqual(mem.getCurrentMemorySize(), 32);
    try testing.expectEqual(mem.buffer.len, 32);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);

    try mem.resize(96);
    try testing.expectEqual(mem.getCurrentMemorySize(), 96);
    try testing.expectEqual(mem.buffer.len, 96);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);

    try mem.resize(64);
    try testing.expectEqual(mem.getCurrentMemorySize(), 64);
    try testing.expectEqual(mem.buffer.len, 64);
    try testing.expectEqual(mem.checkpoints.items.len, 0);
    try testing.expectEqual(mem.last_checkpoint, 0);
}

test "Mstore" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.memory.mstoreInstruction(&interpreter);

        try testing.expectEqual(69, interpreter.memory.wordToInt(0));
        try testing.expectEqual(6, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(1);

        try evm.instructions.memory.mstoreInstruction(&interpreter);

        try testing.expectEqual(69, interpreter.memory.wordToInt(1));
        try testing.expectEqual(12, interpreter.gas_tracker.usedAmount());
    }
}

test "Mstore8" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(0xFFFF);
        try interpreter.stack.pushUnsafe(0);

        try evm.instructions.memory.mstore8Instruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.memory.getMemoryByte(0));
        try testing.expectEqual(6, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0x1F);
        try interpreter.stack.pushUnsafe(1);

        try evm.instructions.memory.mstore8Instruction(&interpreter);

        try testing.expectEqual(0x1F, interpreter.memory.getMemoryByte(1));
        try testing.expectEqual(9, interpreter.gas_tracker.usedAmount());
    }
}

test "Msize" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    {
        try evm.instructions.memory.msizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
    }
    {
        try evm.instructions.memory.msizeInstruction(&interpreter);
        try evm.instructions.memory.mloadInstruction(&interpreter);
        try evm.instructions.memory.msizeInstruction(&interpreter);

        try testing.expectEqual(32, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(12, interpreter.gas_tracker.usedAmount());
    }
}

test "MCopy" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.spec = .LATEST;

    try interpreter.stack.pushUnsafe(0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
    try interpreter.stack.pushUnsafe(32);
    try evm.instructions.memory.mstoreInstruction(&interpreter);

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);

    try evm.instructions.memory.mcopyInstruction(&interpreter);

    try testing.expectEqual(0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, interpreter.memory.wordToInt(0));
    try testing.expectEqual(15, interpreter.gas_tracker.usedAmount());

    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, evm.instructions.memory.mcopyInstruction(&interpreter));
    }
}
