const evm_mod = @import("zabi").evm;
const std = @import("std");
const testing = std.testing;

const Contract = evm_mod.contract.Contract;
const EVM = evm_mod.EVM;
const PlainHost = evm_mod.host.PlainHost;

test "EVM basic initialization and deinitialization" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
    try testing.expectEqual(@as(usize, 0), vm.return_data.len);
}

test "EVM simple bytecode execution - PUSH1 ADD STOP" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    // Configure the environment through the Host
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01, 0x00 }) };

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
    try testing.expect(result.gas_used > 0);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
    try testing.expectEqual(@as(usize, 0), vm.return_data.len);
}

test "EVM depth limit enforcement" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    try testing.expectEqual(@as(usize, 1024), EVM.MAX_CALL_STACK_DEPTH);
}

test "EVM CREATE address derivation" {
    const sender: [20]u8 = [_]u8{0x0a} ** 20;

    const addr_nonce_0 = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 0 });
    const addr_nonce_1 = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 1 });

    try testing.expect(!std.mem.eql(u8, &addr_nonce_0, &addr_nonce_1));

    const addr_nonce_0_again = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 0 });
    try testing.expectEqualSlices(u8, &addr_nonce_0, &addr_nonce_0_again);
}

test "EVM CREATE2 address derivation" {
    const sender: [20]u8 = [_]u8{0x0b} ** 20;
    const salt: u256 = 12345;
    const init_code = &[_]u8{ 0x60, 0x00, 0x60, 0x00, 0xf3 };

    const addr1 = EVM.deriveCreate2Address(sender, salt, init_code);
    const addr2 = EVM.deriveCreate2Address(sender, salt + 1, init_code);

    try testing.expect(!std.mem.eql(u8, &addr1, &addr2));

    const addr1_again = EVM.deriveCreate2Address(sender, salt, init_code);
    try testing.expectEqualSlices(u8, &addr1, &addr1_again);
}

test "EVM ExecutionResult deinit" {
    const output = try testing.allocator.alloc(u8, 10);
    @memset(output, 0xab);

    var result = EVM.ExecutionResult{
        .status = .stopped,
        .output = output,
        .gas_used = 100,
        .gas_refunded = 0,
    };

    result.deinit(testing.allocator);
}

test "EVM CallFrame deinit" {
    const contract = try Contract.init(
        testing.allocator,
        &[_]u8{},
        .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x00 }) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );

    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: evm_mod.Interpreter = undefined;
    try interpreter.init(testing.allocator, &contract, plain.host(), .{});

    var frame: EVM.CallFrame = .{
        .contract = contract,
        .interpreter = interpreter,
        .return_memory_offset = .{ 0, 0 },
        .is_create = false,
        .checkpoint = .{ .journal_checkpoint = 0, .logs_checkpoint = 0 },
    };

    frame.deinit(testing.allocator);
}

test "Host checkpoint operations - PlainHost no-op" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    const host = plain.host();

    // PlainHost checkpoint returns a dummy checkpoint
    const cp = try host.checkpoint();
    try testing.expectEqual(@as(usize, 0), cp.journal_checkpoint);
    try testing.expectEqual(@as(usize, 0), cp.logs_checkpoint);

    // commit and revert are no-ops for PlainHost
    host.commitCheckpoint();
    try host.revertCheckpoint(cp);
}

test "EVM checkpoint integration - creates checkpoint per frame" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // PUSH1 0x01, PUSH1 0x02, ADD, STOP
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01, 0x00 }) };

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    // Execution should succeed and call stack should be empty
    try testing.expectEqual(.stopped, result.status);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM checkpoint integration - RETURN with data" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // PUSH1 0x42, PUSH1 0x00, MSTORE, PUSH1 0x20, PUSH1 0x00, RETURN
    // Store 0x42 at memory[0], then return 32 bytes from offset 0
    const code: evm_mod.bytecode.Bytecode = .{
        .raw = @constCast(&[_]u8{
            0x60, 0x42, // PUSH1 0x42
            0x60, 0x00, // PUSH1 0x00
            0x52, // MSTORE
            0x60, 0x20, // PUSH1 0x20
            0x60, 0x00, // PUSH1 0x00
            0xf3, // RETURN
        }),
    };

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    // Execution should return successfully
    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    // The value 0x42 should be at the end of the 32-byte word (big-endian)
    try testing.expectEqual(@as(u8, 0x42), result.output[31]);
}

test "EVM failure - REVERT returns InterpreterReverted error" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // PUSH1 0x00, PUSH1 0x00, REVERT (revert with empty data)
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x00, 0x60, 0x00, 0xfd }) };

    const result = vm.executeBytecode(code);

    // REVERT causes InterpreterReverted error
    try testing.expectError(error.InterpreterReverted, result);
    // Call stack should be cleaned up on error
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM failure - INVALID opcode returns error" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // INVALID opcode (0xfe)
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{0xfe}) };

    const result = vm.executeBytecode(code);

    // INVALID causes InvalidInstructionOpcode error
    try testing.expectError(error.InvalidInstructionOpcode, result);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM failure - stack underflow returns error" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // ADD without any values on stack causes underflow
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{0x01}) };

    const result = vm.executeBytecode(code);

    try testing.expectError(error.StackUnderflow, result);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM failure - out of gas returns error" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 1, // Very low gas limit
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, plain.host());

    // PUSH1 0x01, PUSH1 0x02, ADD - requires more than 1 gas
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }) };

    const result = vm.executeBytecode(code);

    try testing.expectError(error.OutOfGas, result);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM failure - invalid jump destination returns error" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    vm.init(testing.allocator, plain.host());
    defer vm.deinit();

    // PUSH1 0xFF, JUMP - jump to invalid destination
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0xff, 0x56 }) };

    const result = vm.executeBytecode(code);

    try testing.expectError(error.InvalidJump, result);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "EVM gas accounting - successful execution tracks gas correctly" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    vm.init(testing.allocator, plain.host());
    defer vm.deinit();

    // PUSH1 (3 gas) + PUSH1 (3 gas) + ADD (3 gas) + STOP (0 gas) = 9 gas
    const code: evm_mod.bytecode.Bytecode = .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01, 0x00 }) };

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
    try testing.expectEqual(@as(u64, 9), result.gas_used);
    try testing.expectEqual(@as(i64, 0), result.gas_refunded);
}

test "EVM multiple operations - complex arithmetic" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);
    plain.env = .initDefaultWithTransaction(.{
        .caller = [_]u8{1} ** 20,
        .gas_limit = 100_000,
        .transact_to = .{ .call = [_]u8{2} ** 20 },
    });

    var vm: EVM = undefined;
    vm.init(testing.allocator, plain.host());
    defer vm.deinit();

    // (3 + 5) * 2 = 16
    // PUSH1 0x03, PUSH1 0x05, ADD, PUSH1 0x02, MUL, PUSH1 0x00, MSTORE, PUSH1 0x20, PUSH1 0x00, RETURN
    const code: evm_mod.bytecode.Bytecode = .{
        .raw = @constCast(&[_]u8{
            0x60, 0x03, // PUSH1 3
            0x60, 0x05, // PUSH1 5
            0x01, // ADD -> 8
            0x60, 0x02, // PUSH1 2
            0x02, // MUL -> 16
            0x60, 0x00, // PUSH1 0
            0x52, // MSTORE
            0x60, 0x20, // PUSH1 32
            0x60, 0x00, // PUSH1 0
            0xf3, // RETURN
        }),
    };

    var result = try vm.executeBytecode(code);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    // Result 16 (0x10) should be at the end of the 32-byte word
    try testing.expectEqual(@as(u8, 0x10), result.output[31]);
}
