const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const evm = @import("zabi").evm;
const Contract = evm.contract.Contract;
const Interpreter = evm.Interpreter;
const PlainHost = evm.host.PlainHost;

test "And" {
    // PUSH1 0x7f, PUSH1 0x7f, AND
    const code = [_]u8{ 0x60, 0x7f, 0x60, 0x7f, 0x16 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

    try testing.expectEqual(0x7f, try interpreter.stack.tryPopUnsafe());
}

test "Or" {
    // PUSH1 0x0f, PUSH1 0xf0, OR
    const code = [_]u8{ 0x60, 0x0f, 0x60, 0xf0, 0x17 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

    try testing.expectEqual(0xff, try interpreter.stack.tryPopUnsafe());
}

test "Xor" {
    // PUSH1 0x7f, PUSH1 0x7f, XOR
    const code = [_]u8{ 0x60, 0x7f, 0x60, 0x7f, 0x18 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Greater than" {
    // PUSH1 0x7f, PUSH1 0x7f, GT -> 0 (not greater)
    const code = [_]u8{ 0x60, 0x7f, 0x60, 0x7f, 0x11 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Lower than" {
    // PUSH1 0x7f, PUSH1 0x7f, LT -> 0 (not less)
    const code = [_]u8{ 0x60, 0x7f, 0x60, 0x7f, 0x10 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Equal" {
    // PUSH1 0x7f, PUSH1 0x7f, EQ -> 1 (equal)
    const code = [_]u8{ 0x60, 0x7f, 0x60, 0x7f, 0x14 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "IsZero" {
    // PUSH1 0x00, ISZERO -> 1 (is zero)
    const code = [_]u8{ 0x60, 0x00, 0x15 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Signed Greater than" {
    // PUSH32 maxInt(u256)-1, PUSH32 maxInt(u256), SGT
    // In signed: -2 > -1 -> true (1)
    var code: [67]u8 = undefined;
    code[0] = 0x7f; // PUSH32
    @memset(code[1..33], 0xff);
    code[32] = 0xfe; // last byte = 0xfe -> maxInt - 1
    code[33] = 0x7f; // PUSH32
    @memset(code[34..66], 0xff); // maxInt(u256)
    code[66] = 0x13; // SGT

    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Signed Lower than" {
    // PUSH32 maxInt(u256), PUSH32 maxInt(u256)-1, SLT
    // In signed: -1 < -2 -> true (1)
    var code: [67]u8 = undefined;
    code[0] = 0x7f; // PUSH32
    @memset(code[1..33], 0xff); // maxInt(u256)
    code[33] = 0x7f; // PUSH32
    @memset(code[34..66], 0xff);
    code[65] = 0xfe; // last byte = 0xfe -> maxInt - 1
    code[66] = 0x12; // SLT

    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Shift Left" {
    // PUSH1 2, PUSH1 1, SHL -> 2 << 1 = 4
    const code = [_]u8{ 0x60, 0x02, 0x60, 0x01, 0x1b };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

    try testing.expectEqual(4, try interpreter.stack.tryPopUnsafe());
}

test "Shift Right" {
    // PUSH1 2, PUSH1 1, SHR -> 2 >> 1 = 1
    const code = [_]u8{ 0x60, 0x02, 0x60, 0x01, 0x1c };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "SAR" {
    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0);
        try interpreter.stack.pushUnsafe(4);

        try evm.instructions.bitwise.signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.usedAmount());
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try evm.instructions.bitwise.signedShiftRightInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.usedAmount());
    }
}

test "SAR bytecode" {
    // PUSH1 2, PUSH1 1, SAR -> 2 >> 1 = 1 (unsigned value, no sign extension)
    const code = [_]u8{ 0x60, 0x02, 0x60, 0x01, 0x1d };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Not" {
    // PUSH1 0x00, NOT -> maxInt(u256)
    const code = [_]u8{ 0x60, 0x00, 0x19 };
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&code) },
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

test "Byte" {
    {
        // PUSH1 0xFF, PUSH1 0x1F, BYTE -> get byte at position 31 (last byte)
        const code = [_]u8{ 0x60, 0xff, 0x60, 0x1f, 0x1a };
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&code) },
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

        try testing.expectEqual(0xff, try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH2 0xFF00, PUSH1 0x1E, BYTE -> get byte at position 30
        const code = [_]u8{ 0x61, 0xff, 0x00, 0x60, 0x1e, 0x1a };
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&code) },
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

        try testing.expectEqual(0xff, try interpreter.stack.tryPopUnsafe());
    }
    {
        // PUSH2 0xFFFE, PUSH1 0x1F, BYTE -> get byte at position 31
        const code = [_]u8{ 0x61, 0xff, 0xfe, 0x60, 0x1f, 0x1a };
        const contract_instance = try Contract.init(
            testing.allocator,
            &.{},
            .{ .raw = @constCast(&code) },
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

        try testing.expectEqual(0xfe, try interpreter.stack.tryPopUnsafe());
    }
}
