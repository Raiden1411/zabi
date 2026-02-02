const std = @import("std");
const instructions = @import("instructions/root.zig");

const EnumFieldStruct = std.enums.EnumFieldStruct;
const Interpreter = @import("Interpreter.zig");

/// Comptime generated table from EVM instructions.
pub const instruction_table = InstructionTable.generateTable(.{
    .STOP = .{ .execution = instructions.control.stopInstruction, .min_stack = stackBounds(1024, 0, 0).min_stack, .max_stack = stackBounds(1024, 0, 0).max_stack },
    .ADD = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .MUL = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SUB = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .DIV = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SDIV = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .MOD = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SMOD = .{ .execution = instructions.arithmetic.signedModInstruction, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .ADDMOD = .{ .execution = instructions.arithmetic.modAdditionInstruction, .min_stack = stackBounds(1024, 3, 1).min_stack, .max_stack = stackBounds(1024, 3, 1).max_stack },
    .MULMOD = .{ .execution = instructions.arithmetic.modMultiplicationInstruction, .min_stack = stackBounds(1024, 3, 1).min_stack, .max_stack = stackBounds(1024, 3, 1).max_stack },
    .EXP = .{ .execution = instructions.arithmetic.exponentInstruction, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SIGNEXTEND = .{ .execution = instructions.arithmetic.signExtendInstruction, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .LT = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .GT = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SLT = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SGT = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .EQ = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .ISZERO = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .AND = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .OR = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .XOR = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .NOT = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .BYTE = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SHL = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SHR = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .SAR = .{ .execution = instructions.bitwise.signedShiftRightInstruction, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .KECCAK256 = .{ .execution = instructions.system.keccakInstruction, .min_stack = stackBounds(1024, 2, 1).min_stack, .max_stack = stackBounds(1024, 2, 1).max_stack },
    .ADDRESS = .{ .execution = instructions.system.addressInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .BALANCE = .{ .execution = instructions.host.balanceInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .ORIGIN = .{ .execution = instructions.enviroment.originInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CALLER = .{ .execution = instructions.system.callerInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CALLVALUE = .{ .execution = instructions.system.callValueInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CALLDATALOAD = .{ .execution = instructions.system.callDataLoadInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .CALLDATASIZE = .{ .execution = instructions.system.callDataSizeInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CALLDATACOPY = .{ .execution = instructions.system.callDataCopyInstruction, .min_stack = stackBounds(1024, 3, 0).min_stack, .max_stack = stackBounds(1024, 3, 0).max_stack },
    .CODESIZE = .{ .execution = instructions.system.codeSizeInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CODECOPY = .{ .execution = instructions.system.codeCopyInstruction, .min_stack = stackBounds(1024, 3, 0).min_stack, .max_stack = stackBounds(1024, 3, 0).max_stack },
    .GASPRICE = .{ .execution = instructions.enviroment.gasPriceInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .EXTCODESIZE = .{ .execution = instructions.host.extCodeSizeInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .EXTCODECOPY = .{ .execution = instructions.host.extCodeSizeInstruction, .min_stack = stackBounds(1024, 4, 0).min_stack, .max_stack = stackBounds(1024, 4, 0).max_stack },
    .RETURNDATASIZE = .{ .execution = instructions.system.returnDataSizeInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .RETURNDATACOPY = .{ .execution = instructions.system.returnDataCopyInstruction, .min_stack = stackBounds(1024, 3, 0).min_stack, .max_stack = stackBounds(1024, 3, 0).max_stack },
    .EXTCODEHASH = .{ .execution = instructions.host.extCodeHashInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .BLOCKHASH = .{ .execution = instructions.host.blockHashInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .COINBASE = .{ .execution = instructions.enviroment.coinbaseInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .TIMESTAMP = .{ .execution = instructions.enviroment.timestampInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .NUMBER = .{ .execution = instructions.enviroment.blockNumberInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PREVRANDAO = .{ .execution = instructions.enviroment.difficultyInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .GASLIMIT = .{ .execution = instructions.enviroment.gasLimitInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .CHAINID = .{ .execution = instructions.enviroment.chainIdInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .SELFBALANCE = .{ .execution = instructions.host.selfBalanceInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .BASEFEE = .{ .execution = instructions.enviroment.baseFeeInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .BLOBHASH = .{ .execution = instructions.enviroment.blobHashInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .BLOBBASEFEE = .{ .execution = instructions.enviroment.blobBaseFeeInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .POP = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 0).min_stack, .max_stack = stackBounds(1024, 1, 0).max_stack },
    .MLOAD = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .MSTORE = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .MSTORE8 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .SLOAD = .{ .execution = instructions.host.sloadInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .SSTORE = .{ .execution = instructions.host.sstoreInstruction, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },

    .JUMP = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 0).min_stack, .max_stack = stackBounds(1024, 1, 0).max_stack },
    .JUMPI = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .PC = .{ .execution = instructions.control.programCounterInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .MSIZE = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .GAS = .{ .execution = instructions.system.gasInstruction, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .JUMPDEST = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 0).min_stack, .max_stack = stackBounds(1024, 0, 0).max_stack },
    .TLOAD = .{ .execution = instructions.host.tloadInstruction, .min_stack = stackBounds(1024, 1, 1).min_stack, .max_stack = stackBounds(1024, 1, 1).max_stack },
    .TSTORE = .{ .execution = instructions.host.tstoreInstruction, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .MCOPY = .{ .execution = instructions.memory.mcopyInstruction, .min_stack = stackBounds(1024, 3, 0).min_stack, .max_stack = stackBounds(1024, 3, 0).max_stack },
    .PUSH0 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH1 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH2 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH3 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH4 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH5 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH6 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH7 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH8 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH9 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH10 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH11 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH12 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH13 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH14 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH15 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH16 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH17 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH18 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH19 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH20 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH21 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH22 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH23 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH24 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH25 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH26 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH27 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH28 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH29 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH30 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH31 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .PUSH32 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 0, 1).min_stack, .max_stack = stackBounds(1024, 0, 1).max_stack },
    .DUP1 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 1, 2).min_stack, .max_stack = stackBounds(1024, 1, 2).max_stack },
    .DUP2 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 3).min_stack, .max_stack = stackBounds(1024, 2, 3).max_stack },
    .DUP3 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 3, 4).min_stack, .max_stack = stackBounds(1024, 3, 4).max_stack },
    .DUP4 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 4, 5).min_stack, .max_stack = stackBounds(1024, 4, 5).max_stack },
    .DUP5 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 5, 6).min_stack, .max_stack = stackBounds(1024, 5, 6).max_stack },
    .DUP6 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 6, 7).min_stack, .max_stack = stackBounds(1024, 6, 7).max_stack },
    .DUP7 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 7, 8).min_stack, .max_stack = stackBounds(1024, 7, 8).max_stack },
    .DUP8 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 8, 9).min_stack, .max_stack = stackBounds(1024, 8, 9).max_stack },
    .DUP9 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 9, 10).min_stack, .max_stack = stackBounds(1024, 9, 10).max_stack },
    .DUP10 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 10, 11).min_stack, .max_stack = stackBounds(1024, 10, 11).max_stack },
    .DUP11 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 11, 12).min_stack, .max_stack = stackBounds(1024, 11, 12).max_stack },
    .DUP12 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 12, 13).min_stack, .max_stack = stackBounds(1024, 12, 13).max_stack },
    .DUP13 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 13, 14).min_stack, .max_stack = stackBounds(1024, 13, 14).max_stack },
    .DUP14 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 14, 15).min_stack, .max_stack = stackBounds(1024, 14, 15).max_stack },
    .DUP15 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 15, 16).min_stack, .max_stack = stackBounds(1024, 15, 16).max_stack },
    .DUP16 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 16, 17).min_stack, .max_stack = stackBounds(1024, 16, 17).max_stack },
    .SWAP1 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 2, 2).min_stack, .max_stack = stackBounds(1024, 2, 2).max_stack },
    .SWAP2 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 3, 3).min_stack, .max_stack = stackBounds(1024, 3, 3).max_stack },
    .SWAP3 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 4, 4).min_stack, .max_stack = stackBounds(1024, 4, 4).max_stack },
    .SWAP4 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 5, 5).min_stack, .max_stack = stackBounds(1024, 5, 5).max_stack },
    .SWAP5 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 6, 6).min_stack, .max_stack = stackBounds(1024, 6, 6).max_stack },
    .SWAP6 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 7, 7).min_stack, .max_stack = stackBounds(1024, 7, 7).max_stack },
    .SWAP7 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 8, 8).min_stack, .max_stack = stackBounds(1024, 8, 8).max_stack },
    .SWAP8 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 9, 9).min_stack, .max_stack = stackBounds(1024, 9, 9).max_stack },
    .SWAP9 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 10, 10).min_stack, .max_stack = stackBounds(1024, 10, 10).max_stack },
    .SWAP10 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 11, 11).min_stack, .max_stack = stackBounds(1024, 11, 11).max_stack },
    .SWAP11 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 12, 12).min_stack, .max_stack = stackBounds(1024, 12, 12).max_stack },
    .SWAP12 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 13, 13).min_stack, .max_stack = stackBounds(1024, 13, 13).max_stack },
    .SWAP13 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 14, 14).min_stack, .max_stack = stackBounds(1024, 14, 14).max_stack },
    .SWAP14 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 15, 15).min_stack, .max_stack = stackBounds(1024, 15, 15).max_stack },
    .SWAP15 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 16, 16).min_stack, .max_stack = stackBounds(1024, 16, 16).max_stack },
    .SWAP16 = .{ .execution = inlinedOpcode, .min_stack = stackBounds(1024, 17, 17).min_stack, .max_stack = stackBounds(1024, 17, 17).max_stack },
    .LOG0 = .{ .execution = makeLogInstruction(0), .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .LOG1 = .{ .execution = makeLogInstruction(1), .min_stack = stackBounds(1024, 3, 0).min_stack, .max_stack = stackBounds(1024, 3, 0).max_stack },
    .LOG2 = .{ .execution = makeLogInstruction(2), .min_stack = stackBounds(1024, 4, 0).min_stack, .max_stack = stackBounds(1024, 4, 0).max_stack },
    .LOG3 = .{ .execution = makeLogInstruction(3), .min_stack = stackBounds(1024, 5, 0).min_stack, .max_stack = stackBounds(1024, 5, 0).max_stack },
    .LOG4 = .{ .execution = makeLogInstruction(4), .min_stack = stackBounds(1024, 6, 0).min_stack, .max_stack = stackBounds(1024, 6, 0).max_stack },
    .CREATE = .{ .execution = makeCreateInstruction(false), .min_stack = stackBounds(1024, 3, 1).min_stack, .max_stack = stackBounds(1024, 3, 1).max_stack },
    .CALL = .{ .execution = instructions.contract.callInstruction, .min_stack = stackBounds(1024, 7, 1).min_stack, .max_stack = stackBounds(1024, 7, 1).max_stack },
    .CALLCODE = .{ .execution = instructions.contract.callCodeInstruction, .min_stack = stackBounds(1024, 7, 1).min_stack, .max_stack = stackBounds(1024, 7, 1).max_stack },
    .RETURN = .{ .execution = instructions.control.returnInstruction, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .DELEGATECALL = .{ .execution = instructions.contract.delegateCallInstruction, .min_stack = stackBounds(1024, 6, 1).min_stack, .max_stack = stackBounds(1024, 6, 1).max_stack },
    .CREATE2 = .{ .execution = makeCreateInstruction(true), .min_stack = stackBounds(1024, 4, 1).min_stack, .max_stack = stackBounds(1024, 4, 1).max_stack },
    .STATICCALL = .{ .execution = instructions.contract.staticCallInstruction, .min_stack = stackBounds(1024, 6, 1).min_stack, .max_stack = stackBounds(1024, 6, 1).max_stack },
    .REVERT = .{ .execution = instructions.control.revertInstruction, .min_stack = stackBounds(1024, 2, 0).min_stack, .max_stack = stackBounds(1024, 2, 0).max_stack },
    .INVALID = .{ .execution = instructions.control.invalidInstruction, .min_stack = stackBounds(1024, 0, 0).min_stack, .max_stack = stackBounds(1024, 0, 0).max_stack },
    .SELFDESTRUCT = .{ .execution = instructions.host.selfDestructInstruction, .min_stack = stackBounds(1024, 1, 0).min_stack, .max_stack = stackBounds(1024, 1, 0).max_stack },
});

/// EVM Opcodes.
pub const Opcodes = enum(u8) {
    // Arithmetic opcodes.
    STOP = 0x00,
    ADD = 0x01,
    MUL = 0x02,
    SUB = 0x03,
    DIV = 0x04,
    SDIV = 0x05,
    MOD = 0x06,
    SMOD = 0x07,
    ADDMOD = 0x08,
    MULMOD = 0x09,
    EXP = 0x0a,
    SIGNEXTEND = 0x0b,

    // Comparision opcodes.
    LT = 0x10,
    GT = 0x11,
    SLT = 0x12,
    SGT = 0x13,
    EQ = 0x14,
    ISZERO = 0x15,
    AND = 0x16,
    OR = 0x17,
    XOR = 0x18,
    NOT = 0x19,
    BYTE = 0x1a,
    SHL = 0x1b,
    SHR = 0x1c,
    SAR = 0x1d,

    // Crypto opcodes.
    KECCAK256 = 0x20,

    // Closure states opcodes.
    ADDRESS = 0x30,
    BALANCE = 0x31,
    ORIGIN = 0x32,
    CALLER = 0x33,
    CALLVALUE = 0x34,
    CALLDATALOAD = 0x35,
    CALLDATASIZE = 0x36,
    CALLDATACOPY = 0x37,
    CODESIZE = 0x38,
    CODECOPY = 0x39,
    GASPRICE = 0x3a,
    EXTCODESIZE = 0x3b,
    EXTCODECOPY = 0x3c,
    RETURNDATASIZE = 0x3d,
    RETURNDATACOPY = 0x3e,
    EXTCODEHASH = 0x3f,

    // Block operations opcodes.
    BLOCKHASH = 0x40,
    COINBASE = 0x41,
    TIMESTAMP = 0x42,
    NUMBER = 0x43,
    PREVRANDAO = 0x44,
    GASLIMIT = 0x45,
    CHAINID = 0x46,
    SELFBALANCE = 0x47,
    BASEFEE = 0x48,
    BLOBHASH = 0x49,
    BLOBBASEFEE = 0x4a,

    // Storage opcodes.
    POP = 0x50,
    MLOAD = 0x51,
    MSTORE = 0x52,
    MSTORE8 = 0x53,
    SLOAD = 0x54,
    SSTORE = 0x55,
    JUMP = 0x56,
    JUMPI = 0x57,
    PC = 0x58,
    MSIZE = 0x59,
    GAS = 0x5a,
    JUMPDEST = 0x5b,
    TLOAD = 0x5c,
    TSTORE = 0x5d,
    MCOPY = 0x5e,
    PUSH0 = 0x5f,

    // Push opcodes
    PUSH1 = 0x60,
    PUSH2 = 0x61,
    PUSH3 = 0x62,
    PUSH4 = 0x63,
    PUSH5 = 0x64,
    PUSH6 = 0x65,
    PUSH7 = 0x66,
    PUSH8 = 0x67,
    PUSH9 = 0x68,
    PUSH10 = 0x69,
    PUSH11 = 0x6a,
    PUSH12 = 0x6b,
    PUSH13 = 0x6c,
    PUSH14 = 0x6d,
    PUSH15 = 0x6e,
    PUSH16 = 0x6f,
    PUSH17 = 0x70,
    PUSH18 = 0x71,
    PUSH19 = 0x72,
    PUSH20 = 0x73,
    PUSH21 = 0x74,
    PUSH22 = 0x75,
    PUSH23 = 0x76,
    PUSH24 = 0x77,
    PUSH25 = 0x78,
    PUSH26 = 0x79,
    PUSH27 = 0x7a,
    PUSH28 = 0x7b,
    PUSH29 = 0x7c,
    PUSH30 = 0x7d,
    PUSH31 = 0x7e,
    PUSH32 = 0x7f,

    // DUP opcodes
    DUP1 = 0x80,
    DUP2 = 0x81,
    DUP3 = 0x82,
    DUP4 = 0x83,
    DUP5 = 0x84,
    DUP6 = 0x85,
    DUP7 = 0x86,
    DUP8 = 0x87,
    DUP9 = 0x88,
    DUP10 = 0x89,
    DUP11 = 0x8a,
    DUP12 = 0x8b,
    DUP13 = 0x8c,
    DUP14 = 0x8d,
    DUP15 = 0x8e,
    DUP16 = 0x8f,

    // Swap opcodes
    SWAP1 = 0x90,
    SWAP2 = 0x91,
    SWAP3 = 0x92,
    SWAP4 = 0x93,
    SWAP5 = 0x94,
    SWAP6 = 0x95,
    SWAP7 = 0x96,
    SWAP8 = 0x97,
    SWAP9 = 0x98,
    SWAP10 = 0x99,
    SWAP11 = 0x9a,
    SWAP12 = 0x9b,
    SWAP13 = 0x9c,
    SWAP14 = 0x9d,
    SWAP15 = 0x9e,
    SWAP16 = 0x9f,

    // Log opcodes
    LOG0 = 0xa0,
    LOG1 = 0xa1,
    LOG2 = 0xa2,
    LOG3 = 0xa3,
    LOG4 = 0xa4,

    // Closure opcodes
    CREATE = 0xf0,
    CALL = 0xf1,
    CALLCODE = 0xf2,
    RETURN = 0xf3,
    DELEGATECALL = 0xf4,
    CREATE2 = 0xf5,

    STATICCALL = 0xfa,
    REVERT = 0xfd,
    INVALID = 0xfe,
    SELFDESTRUCT = 0xff,

    /// Converts `u8` to associated opcode.
    /// Will return null for unknown opcodes
    pub fn toOpcode(num: u8) ?Opcodes {
        return std.enums.fromInt(Opcodes, num);
    }
};

/// EVM instruction table.
pub const InstructionTable = struct {
    /// Array of instructions.
    inner: [256]Operations,

    /// Generates the instruction opcode table.
    /// This is a similar implementation to `std.enums.directEnumArray`
    pub inline fn generateTable(fields: EnumFieldStruct(Opcodes, Operations, null)) InstructionTable {
        const info = @typeInfo(@TypeOf(fields));

        const unknown_bounds = stackBounds(1024, 0, 0);
        var inner: [256]Operations = [_]Operations{.{
            .execution = instructions.control.unknownInstruction,
            .min_stack = unknown_bounds.min_stack,
            .max_stack = unknown_bounds.max_stack,
        }} ** 256;

        inline for (info.@"struct".fields) |field| {
            const value = @field(Opcodes, field.name);
            const index: usize = @intCast(@intFromEnum(value));

            inner[index] = @field(fields, field.name);
        }

        return .{ .inner = inner };
    }
    /// Gets the associated operation for the provided opcode.
    pub inline fn getInstruction(self: *const @This(), opcode_byte: u8) Operations {
        return self.inner[opcode_byte];
    }
};

/// Opcode operations and checks.
pub const Operations = struct {
    /// The execution function attached to the opcode.
    execution: *const fn (ctx: *Interpreter) Interpreter.AllInstructionErrors!void,
    /// The minimum required stack items before executing
    min_stack: u16,
    /// The max allowed size of the stack
    max_stack: u16,
};

/// Creates the log instructions for the instruction table.
pub fn makeLogInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) Interpreter.AllInstructionErrors!void {
    return struct {
        pub fn log(self: *Interpreter) Interpreter.AllInstructionErrors!void {
            return instructions.host.logInstruction(self, swap_size);
        }
    }.log;
}

/// Creates the log instructions for the instruction table.
pub fn makeCreateInstruction(comptime is_create2: bool) *const fn (ctx: *Interpreter) Interpreter.AllInstructionErrors!void {
    return struct {
        pub fn log(self: *Interpreter) Interpreter.AllInstructionErrors!void {
            return instructions.contract.createInstruction(self, is_create2);
        }
    }.log;
}

/// Stack bounds for an opcode operation.
pub const StackBounds = struct {
    min_stack: u16,
    max_stack: u16,
};

/// Sentinel function for opcodes handled inline in Interpreter.run().
/// Using this instead of `undefined` provides safety in debug builds.
fn inlinedOpcode(_: *Interpreter) Interpreter.AllInstructionErrors!void {
    unreachable;
}

/// Calculates the stack bounds for the operation to execute.
pub fn stackBounds(
    comptime limit: comptime_int,
    comptime pop: comptime_int,
    comptime push: comptime_int,
) StackBounds {
    return .{
        .min_stack = @intCast(pop),
        .max_stack = @intCast(limit + pop - push),
    };
}
