const evm = @import("zabi").evm;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const Contract = evm.contract.Contract;
const Interpreter = evm.Interpreter;
const PlainHost = evm.host.PlainHost;

test "Addition" {
    {
        // PUSH1 1, PUSH1 2, ADD => 1 + 2 = 3
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }) },
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

        try testing.expectEqual(3, try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH32 maxInt(u256), PUSH1 1, ADD => overflow to 0
        var code: [35]u8 = undefined;
        code[0] = 0x7f; // PUSH32
        @memset(code[1..33], 0xff); // maxInt(u256)
        code[33] = 0x60; // PUSH1
        code[34] = 0x01; // 1
        // Need ADD opcode
        var full_code: [36]u8 = undefined;
        @memcpy(full_code[0..35], &code);
        full_code[35] = 0x01; // ADD

        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = &full_code },
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
    }
}

test "Multiplication" {
    {
        // PUSH1 1, PUSH1 2, MUL => 1 * 2 = 2
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x02 }) },
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

        try testing.expectEqual(2, try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH32 maxInt(u256), PUSH1 2, MUL => overflow to maxInt(u256) - 1
        var code: [36]u8 = undefined;
        code[0] = 0x7f; // PUSH32
        @memset(code[1..33], 0xff); // maxInt(u256)
        code[33] = 0x60; // PUSH1
        code[34] = 0x02; // 2
        code[35] = 0x02; // MUL

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

        try testing.expectEqual(std.math.maxInt(u256) - 1, try interpreter.stack.tryPopUnsafe());
    }
}

test "Subtraction" {
    {
        // PUSH1 2, PUSH1 1, SUB => 1 - 2 = maxInt(u256) (underflow)
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x02, 0x60, 0x01, 0x03 }) },
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

        try testing.expectEqual(std.math.maxInt(u256), try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH1 1, PUSH1 2, SUB => 2 - 1 = 1
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x03 }) },
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

        try testing.expectEqual(1, try interpreter.stack.tryPopUnsafe());
    }
}

test "Division" {
    {
        // PUSH1 2, PUSH1 1, DIV => 1 / 2 = 0
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x02, 0x60, 0x01, 0x04 }) },
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
    }
    {
        // PUSH1 1, PUSH1 2, DIV => 2 / 1 = 2
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x04 }) },
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

        try testing.expectEqual(2, try interpreter.stack.tryPopUnsafe());
    }
}

test "Signed Division" {
    {
        // PUSH1 2, PUSH32 maxInt(u256) (=-1 signed), SDIV => -1 / 2 = 0
        var code: [36]u8 = undefined;
        code[0] = 0x60; // PUSH1
        code[1] = 0x02; // 2
        code[2] = 0x7f; // PUSH32
        @memset(code[3..35], 0xff); // maxInt(u256) = -1 as i256
        code[35] = 0x05; // SDIV

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

        try testing.expectEqual(0, @as(i256, @bitCast(try interpreter.stack.tryPopUnsafe())));
    }
    {
        // PUSH1 1, PUSH1 2, DIV => 2 / 1 = 2
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x04 }) },
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

        try testing.expectEqual(2, try interpreter.stack.tryPopUnsafe());
    }
}

test "Mod" {
    {
        // PUSH1 2, PUSH1 1, MOD => 1 % 2 = 1
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x02, 0x60, 0x01, 0x06 }) },
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

        try testing.expectEqual(1, try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH1 1, PUSH1 2, MOD => 2 % 1 = 0
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x06 }) },
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
        try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);
        try evm.instructions.arithmetic.signedModInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(8, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.modAdditionInstruction(&interpreter);
        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(8, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(4);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try evm.instructions.arithmetic.modMultiplicationInstruction(&interpreter);
        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(60, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u16));
        try evm.instructions.arithmetic.exponentInstruction(&interpreter);
        try testing.expectEqual(std.math.maxInt(u16), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(120, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.arithmetic.signExtendInstruction(&interpreter);
        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0xFF);
        try evm.instructions.arithmetic.signExtendInstruction(&interpreter);
        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(15, interpreter.gas_tracker.usedAmount());
    }
}
