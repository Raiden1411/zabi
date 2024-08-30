const std = @import("std");
const testing = std.testing;

const Contract = @import("../../evm/contract.zig").Contract;
const Interpreter = @import("../../evm/Interpreter.zig");
const PlainHost = @import("../../evm/host.zig").PlainHost;

test "Init" {
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});
}

test "RunInstruction" {
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

    try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});

    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .return_action);
    try testing.expectEqual(.stopped, result.return_action.result);
    try testing.expectEqual(9, result.return_action.gas.used_amount);
    try testing.expectEqual(3, try interpreter.stack.tryPopUnsafe());
}

test "RunInstruction Create" {
    // Example taken from evm.codes
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{ 0x6c, 0x63, 0xFF, 0xFF, 0xFF, 0xFF, 0x60, 0x00, 0x52, 0x60, 0x04, 0x60, 0x1C, 0xF3, 0x60, 0x00, 0x52, 0x60, 0x0d, 0x60, 0x13, 0x60, 0x00, 0xF0 }) },
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

    try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});

    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .create_action);
    try testing.expect(result.create_action.scheme == .create);
    try testing.expect(interpreter.status == .call_or_create);
    try testing.expectEqual(29531751, interpreter.gas_tracker.used_amount);

    const int: u104 = @byteSwap(@as(u104, @bitCast([_]u8{ 0x63, 0xFF, 0xFF, 0xFF, 0xFF, 0x60, 0x00, 0x52, 0x60, 0x04, 0x60, 0x1C, 0xF3 })));
    const buffer: [13]u8 = @bitCast(int);

    try testing.expectEqualSlices(u8, &buffer, result.create_action.init_code);
}

test "RunInstruction Create2" {
    // Example taken from evm.codes
    const contract_instance = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{ 0x6c, 0x63, 0xFF, 0xFF, 0xFF, 0xFF, 0x60, 0x00, 0x52, 0x60, 0x04, 0x60, 0x1C, 0xF3, 0x60, 0x00, 0x52, 0x60, 0x02, 0x60, 0x0d, 0x60, 0x13, 0x60, 0x00, 0xF5 }) },
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

    try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});

    const result = try interpreter.run();
    defer result.deinit(testing.allocator);

    try testing.expect(result == .create_action);
    try testing.expect(result.create_action.scheme == .create2);
    try testing.expect(interpreter.status == .call_or_create);
    try testing.expectEqual(29531751, interpreter.gas_tracker.used_amount);

    const int: u104 = @byteSwap(@as(u104, @bitCast([_]u8{ 0x63, 0xFF, 0xFF, 0xFF, 0xFF, 0x60, 0x00, 0x52, 0x60, 0x04, 0x60, 0x1C, 0xF3 })));
    const buffer: [13]u8 = @bitCast(int);

    try testing.expectEqualSlices(u8, &buffer, result.create_action.init_code);
}

test "Running With Jump" {
    {
        var code = [_]u8{ 0x60, 0x04, 0x56, 0xfd, 0x5b, 0x60, 0x01 };
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

        try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});

        const result = try interpreter.run();
        defer result.deinit(testing.allocator);

        try testing.expect(result == .return_action);
        try testing.expectEqual(.stopped, result.return_action.result);
        try testing.expectEqual(15, result.return_action.gas.used_amount);
    }
    {
        var code = [_]u8{ 0x60, 0x03, 0x56, 0xfd, 0x5b, 0x60, 0x01 };
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

        try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});

        try testing.expectError(error.InvalidJump, interpreter.run());
    }
}
