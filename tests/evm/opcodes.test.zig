const evm = @import("zabi").evm;
const std = @import("std");
const testing = std.testing;

test "Opcode table wiring" {
    const table = evm.opcode.instruction_table;
    const Opcodes = evm.opcode.Opcodes;

    {
        const op = table.getInstruction(@intFromEnum(Opcodes.EXTCODECOPY));
        try testing.expect(op.execution == evm.instructions.host.extCodeCopyInstruction);
        try testing.expectEqual(@as(u16, 4), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.EXTCODESIZE));
        try testing.expect(op.execution == evm.instructions.host.extCodeSizeInstruction);
        try testing.expectEqual(@as(u16, 1), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.EXTCODEHASH));
        try testing.expect(op.execution == evm.instructions.host.extCodeHashInstruction);
        try testing.expectEqual(@as(u16, 1), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.CALLDATALOAD));
        try testing.expect(op.execution == evm.instructions.system.callDataLoadInstruction);
        try testing.expectEqual(@as(u16, 1), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.CALLDATACOPY));
        try testing.expect(op.execution == evm.instructions.system.callDataCopyInstruction);
        try testing.expectEqual(@as(u16, 3), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.RETURNDATASIZE));
        try testing.expect(op.execution == evm.instructions.system.returnDataSizeInstruction);
        try testing.expectEqual(@as(u16, 0), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.RETURNDATACOPY));
        try testing.expect(op.execution == evm.instructions.system.returnDataCopyInstruction);
        try testing.expectEqual(@as(u16, 3), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.PREVRANDAO));
        try testing.expect(op.execution == evm.instructions.enviroment.difficultyInstruction);
        try testing.expectEqual(@as(u16, 0), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.TLOAD));
        try testing.expect(op.execution == evm.instructions.host.tloadInstruction);
        try testing.expectEqual(@as(u16, 1), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.TSTORE));
        try testing.expect(op.execution == evm.instructions.host.tstoreInstruction);
        try testing.expectEqual(@as(u16, 2), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.MCOPY));
        try testing.expect(op.execution == evm.instructions.memory.mcopyInstruction);
        try testing.expectEqual(@as(u16, 3), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.RETURN));
        try testing.expect(op.execution == evm.instructions.control.returnInstruction);
        try testing.expectEqual(@as(u16, 2), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.REVERT));
        try testing.expect(op.execution == evm.instructions.control.revertInstruction);
        try testing.expectEqual(@as(u16, 2), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.INVALID));
        try testing.expect(op.execution == evm.instructions.control.invalidInstruction);
        try testing.expectEqual(@as(u16, 0), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.SELFDESTRUCT));
        try testing.expect(op.execution == evm.instructions.host.selfDestructInstruction);
        try testing.expectEqual(@as(u16, 1), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.CALL));
        try testing.expect(op.execution == evm.instructions.contract.callInstruction);
        try testing.expectEqual(@as(u16, 7), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.CALLCODE));
        try testing.expect(op.execution == evm.instructions.contract.callCodeInstruction);
        try testing.expectEqual(@as(u16, 7), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.DELEGATECALL));
        try testing.expect(op.execution == evm.instructions.contract.delegateCallInstruction);
        try testing.expectEqual(@as(u16, 6), op.min_stack);
    }
    {
        const op = table.getInstruction(@intFromEnum(Opcodes.STATICCALL));
        try testing.expect(op.execution == evm.instructions.contract.staticCallInstruction);
        try testing.expectEqual(@as(u16, 6), op.min_stack);
    }
}

test "Fork-gated opcode enablement and Prague/Cancun parity" {
    const GatedOpcode = evm.fork_rules.GatedOpcode;
    const SpecId = evm.specification.SpecId;

    const checks = [_]struct { opcode: GatedOpcode, disabled_at: SpecId, enabled_at: SpecId }{
        .{ .opcode = .REVERT, .disabled_at = .HOMESTEAD, .enabled_at = .BYZANTIUM },
        .{ .opcode = .RETURNDATASIZE, .disabled_at = .HOMESTEAD, .enabled_at = .BYZANTIUM },
        .{ .opcode = .CHAINID, .disabled_at = .PETERSBURG, .enabled_at = .ISTANBUL },
        .{ .opcode = .SELFBALANCE, .disabled_at = .PETERSBURG, .enabled_at = .ISTANBUL },
        .{ .opcode = .CREATE2, .disabled_at = .BYZANTIUM, .enabled_at = .PETERSBURG },
        .{ .opcode = .DELEGATECALL, .disabled_at = .FRONTIER, .enabled_at = .HOMESTEAD },
        .{ .opcode = .STATICCALL, .disabled_at = .HOMESTEAD, .enabled_at = .BYZANTIUM },
        .{ .opcode = .PUSH0, .disabled_at = .MERGE, .enabled_at = .SHANGHAI },
        .{ .opcode = .BLOBHASH, .disabled_at = .SHANGHAI, .enabled_at = .CANCUN },
        .{ .opcode = .BLOBBASEFEE, .disabled_at = .SHANGHAI, .enabled_at = .CANCUN },
        .{ .opcode = .TLOAD, .disabled_at = .SHANGHAI, .enabled_at = .CANCUN },
        .{ .opcode = .TSTORE, .disabled_at = .SHANGHAI, .enabled_at = .CANCUN },
        .{ .opcode = .MCOPY, .disabled_at = .SHANGHAI, .enabled_at = .CANCUN },
    };

    inline for (checks) |check| {
        try testing.expect(!check.opcode.isEnabled(check.disabled_at));
        try testing.expect(check.opcode.isEnabled(check.enabled_at));
    }

    inline for (std.meta.tags(GatedOpcode)) |opcode| {
        try testing.expectEqual(opcode.isEnabled(.CANCUN), opcode.isEnabled(.PRAGUE));
    }
}

test "Prague and Cancun gas schedule parity for selected costs" {
    const gas = evm.gas;
    const SelfDestructResult = evm.host.SelfDestructResult;

    try testing.expectEqual(
        gas.calculateCallCost(.CANCUN, true, true, true),
        gas.calculateCallCost(.PRAGUE, true, true, true),
    );
    try testing.expectEqual(
        gas.calculateCodeSizeCost(.CANCUN, true),
        gas.calculateCodeSizeCost(.PRAGUE, true),
    );
    try testing.expectEqual(
        gas.calculateSloadCost(.CANCUN, true),
        gas.calculateSloadCost(.PRAGUE, true),
    );
    try testing.expectEqual(
        gas.calculateSloadCost(.CANCUN, false),
        gas.calculateSloadCost(.PRAGUE, false),
    );
    try testing.expectEqual(
        gas.calculateSstoreCost(.CANCUN, 1, 1, 2, 100_000, true),
        gas.calculateSstoreCost(.PRAGUE, 1, 1, 2, 100_000, true),
    );
    try testing.expectEqual(
        gas.calculateSelfDestructCost(.CANCUN, SelfDestructResult{
            .had_value = true,
            .target_exists = false,
            .is_cold = true,
            .previously_destroyed = false,
        }),
        gas.calculateSelfDestructCost(.PRAGUE, SelfDestructResult{
            .had_value = true,
            .target_exists = false,
            .is_cold = true,
            .previously_destroyed = false,
        }),
    );
}
