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
