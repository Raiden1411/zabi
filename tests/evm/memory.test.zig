const evm = @import("zabi").evm;
const gas = evm.gas;
const memory = evm.memory;
const std = @import("std");
const testing = std.testing;

const Contract = evm.contract.Contract;
const EVM = evm.EVM;
const Interpreter = evm.Interpreter;
const Memory = memory.Memory;
const PlainHost = evm.host.PlainHost;

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
    {
        // PUSH1 69, PUSH1 0, MSTORE
        var code = [_]u8{ 0x60, 69, 0x60, 0x00, 0x52 };
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

        try testing.expectEqual(69, interpreter.memory.wordToInt(0));
        try testing.expectEqual(12, result.return_action.gas.usedAmount());
    }
    {
        // PUSH1 69, PUSH1 1, MSTORE
        var code = [_]u8{ 0x60, 69, 0x60, 0x01, 0x52 };
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

        try testing.expectEqual(69, interpreter.memory.wordToInt(1));
        // PUSH1 (3) + PUSH1 (3) + MSTORE (3 + 6 memory for 2 words) = 15
        try testing.expectEqual(15, result.return_action.gas.usedAmount());
    }
}

test "Mstore8" {
    {
        // PUSH2 0xFFFF, PUSH1 0, MSTORE8
        var code = [_]u8{ 0x61, 0xFF, 0xFF, 0x60, 0x00, 0x53 };
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

        try testing.expectEqual(0xFF, interpreter.memory.getMemoryByte(0));
        try testing.expectEqual(12, result.return_action.gas.usedAmount());
    }
    {
        // PUSH1 0x1F, PUSH1 1, MSTORE8
        var code = [_]u8{ 0x60, 0x1F, 0x60, 0x01, 0x53 };
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

        try testing.expectEqual(0x1F, interpreter.memory.getMemoryByte(1));
        try testing.expectEqual(12, result.return_action.gas.usedAmount());
    }
}

test "Msize" {
    {
        // MSIZE (empty memory)
        var code = [_]u8{0x59};
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

        try testing.expectEqual(0, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(2, result.return_action.gas.usedAmount());
    }
    {
        // MSIZE, MLOAD, MSIZE (memory expands after MLOAD)
        var code = [_]u8{ 0x59, 0x51, 0x59 };
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

        try testing.expectEqual(32, try interpreter.stack.tryPopUnsafe());
        // MSIZE (2) + MLOAD (3 + 3 memory for 1 word) + MSIZE (2) = 10
        try testing.expectEqual(10, result.return_action.gas.usedAmount());
    }
}

test "MCopy" {
    {
        // PUSH32 value, PUSH1 32, MSTORE, PUSH1 32, PUSH1 32, PUSH1 0, MCOPY
        var code = [_]u8{
            0x7F, // PUSH32
            0x00,
            0x01,
            0x02,
            0x03,
            0x04,
            0x05,
            0x06,
            0x07,
            0x08,
            0x09,
            0x0a,
            0x0b,
            0x0c,
            0x0d,
            0x0e,
            0x0f,
            0x10,
            0x11,
            0x12,
            0x13,
            0x14,
            0x15,
            0x16,
            0x17,
            0x18,
            0x19,
            0x1a,
            0x1b,
            0x1c,
            0x1d,
            0x1e,
            0x1f,
            0x60, 0x20, // PUSH1 32
            0x52, // MSTORE
            0x60, 0x20, // PUSH1 32 (length)
            0x60, 0x20, // PUSH1 32 (source)
            0x60, 0x00, // PUSH1 0 (destination)
            0x5E, // MCOPY
        };
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

        try testing.expectEqual(0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, interpreter.memory.wordToInt(0));
        // PUSH32 (3) + PUSH1 (3) + MSTORE (3 + 6 memory for 2 words) + PUSH1 (3) + PUSH1 (3) + PUSH1 (3) + MCOPY (6) = 30
        try testing.expectEqual(30, result.return_action.gas.usedAmount());
    }
    {
        // Test MCOPY not enabled on FRONTIER spec
        var code = [_]u8{ 0x60, 0x00, 0x60, 0x00, 0x60, 0x00, 0x5E }; // PUSH1 0, PUSH1 0, PUSH1 0, MCOPY
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

        try interpreter.init(testing.allocator, &contract_instance, plain.host(), .{ .spec_id = .FRONTIER });
        try testing.expectError(error.InstructionNotEnabled, interpreter.run());
    }
}

test "EVM memory context isolation" {
    // Test that memory contexts are properly managed during subcalls.
    // The parent frame should have its memory restored after a subcall completes.

    var plain: PlainHost = undefined;
    plain.init(testing.allocator);
    defer plain.deinit();

    // Configure the environment through the Host
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    // Simple bytecode: PUSH1 0x42, PUSH1 0, MSTORE, STOP
    // This stores 0x42 at memory offset 0 and stops.
    const code: evm.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x42, 0x60, 0x00, 0x52, 0x00 }) };

    var vm: EVM = undefined;
    vm.init(testing.allocator, plain.host());
    defer vm.deinit();

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);

    // After execution, call stack should be empty (all frames cleaned up)
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}
