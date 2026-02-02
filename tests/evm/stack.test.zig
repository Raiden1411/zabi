const std = @import("std");
const testing = std.testing;

const Contract = @import("zabi").evm.contract.Contract;
const Interpreter = @import("zabi").evm.Interpreter;
const PlainHost = @import("zabi").evm.host.PlainHost;

test "Push" {
    // PUSH1 0xFF
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0xFF }) },
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

        try testing.expectEqual(0xFF, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(3, result.return_action.gas.usedAmount());
    }
    // PUSH32 (all 0xFF bytes)
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{0x7F} ++ &[_]u8{0xFF} ** 32) },
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
        try testing.expectEqual(3, result.return_action.gas.usedAmount());
    }
    // PUSH20 (all 0xFF bytes)
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{0x73} ++ &[_]u8{0xFF} ** 20) },
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

        try testing.expectEqual(std.math.maxInt(u160), try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(3, result.return_action.gas.usedAmount());
    }
}

test "Push Zero" {
    // PUSH0
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{0x5f}) },
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
    // PUSH0 not enabled on FRONTIER
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{0x5f}) },
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
        try testing.expectError(error.OpcodeNotFound, interpreter.run());
    }
}

test "Dup" {
    // DUP1: push 69, dup it
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 69, 0x80 }) }, // PUSH1 69, DUP1
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

        try testing.expectEqual(69, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(69, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(6, result.return_action.gas.usedAmount());
    }
    // DUP6: push 0xFF, then 5 more values, dup the 6th
    {
        // PUSH1 0xFF, PUSH1 69, PUSH1 69, PUSH1 69, PUSH1 69, PUSH1 69, DUP6
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0xFF, 0x60, 69, 0x60, 69, 0x60, 69, 0x60, 69, 0x60, 69, 0x85 }) },
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

        try testing.expectEqual(0xFF, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(21, result.return_action.gas.usedAmount()); // 6 PUSH1 (18) + DUP6 (3)
    }
}

test "Swap" {
    // SWAP1: push 42, push 69, swap
    {
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 42, 0x60, 69, 0x90 }) }, // PUSH1 42, PUSH1 69, SWAP1
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

        try testing.expectEqual(42, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(69, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(9, result.return_action.gas.usedAmount());
    }
    // SWAP5: push 0xFF, then 5 more values, swap
    {
        // PUSH1 0xFF, PUSH1 69, PUSH1 69, PUSH1 69, PUSH1 69, PUSH1 69, SWAP5
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&[_]u8{ 0x60, 0xFF, 0x60, 69, 0x60, 69, 0x60, 69, 0x60, 69, 0x60, 69, 0x94 }) },
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

        try testing.expectEqual(0xFF, try interpreter.stack.tryPopUnsafe());
        try testing.expectEqual(21, result.return_action.gas.usedAmount()); // 6 PUSH1 (18) + SWAP5 (3)
    }
}

test "Pop" {
    // PUSH0, POP
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{ 0x5f, 0x50 }) }, // PUSH0, POP
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

    try testing.expectEqual(.stopped, result.return_action.result);
    try testing.expectEqual(4, result.return_action.gas.usedAmount()); // PUSH0 (2) + POP (2)
}
