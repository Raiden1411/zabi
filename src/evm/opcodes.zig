const std = @import("std");
const instructions = @import("instructions/root.zig");

const Interpreter = @import("interpreter.zig");

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
    DIFFICULTY = 0x44,
    RANDOM = 0x44,
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
    SWAP1 = 0x91,
    SWAP2 = 0x92,
    SWAP3 = 0x93,
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

    pub fn toOpcode(num: u8) ?Opcodes {
        return std.meta.intToEnum(Opcodes, num) catch null;
    }
};

pub const InstructionTable = struct {
    inner: [256]Operations,

    /// Creates the instruction table.
    pub fn init(interpreter: *Interpreter) InstructionTable {
        var inner: [256]Operations = undefined;

        // Fills the array with unknowInstruction for unknow opcodes.
        {
            for (0..256) |possible_opcode| {
                const opcode_enum = Opcodes.toOpcode(possible_opcode);

                if (opcode_enum) |opcode| {
                    switch (opcode) {
                        .STOP => inner[possible_opcode] = .{ .execution = instructions.control.stopInstruction(interpreter), .max_stack = maxStack(1024, 0, 0) },
                        .ADD => inner[possible_opcode] = .{ .execution = instructions.arithmetic.addInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .MUL => inner[possible_opcode] = .{ .execution = instructions.arithmetic.mulInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SUB => inner[possible_opcode] = .{ .execution = instructions.arithmetic.subInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .DIV => inner[possible_opcode] = .{ .execution = instructions.arithmetic.divInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SDIV => inner[possible_opcode] = .{ .execution = instructions.arithmetic.signedDivInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .MOD => inner[possible_opcode] = .{ .execution = instructions.arithmetic.modInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SMOD => inner[possible_opcode] = .{ .execution = instructions.arithmetic.signedModInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .ADDMOD => inner[possible_opcode] = .{ .execution = instructions.arithmetic.modAdditionInstruction(interpreter), .max_stack = maxStack(1024, 3, 1) },
                        .MULMOD => inner[possible_opcode] = .{ .execution = instructions.arithmetic.modMultiplicationInstruction(interpreter), .max_stack = maxStack(1024, 3, 1) },
                        .EXP => inner[possible_opcode] = .{ .execution = instructions.arithmetic.exponentInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SIGNEXTEND => inner[possible_opcode] = .{ .execution = instructions.arithmetic.signedExponentInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .LT => inner[possible_opcode] = .{ .execution = instructions.bitwise.lowerThanInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .GT => inner[possible_opcode] = .{ .execution = instructions.bitwise.greaterThanInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SLT => inner[possible_opcode] = .{ .execution = instructions.bitwise.signedLowerThanInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SGT => inner[possible_opcode] = .{ .execution = instructions.bitwise.signedGreaterThanInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .EQ => inner[possible_opcode] = .{ .execution = instructions.bitwise.equalInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .ISZERO => inner[possible_opcode] = .{ .execution = instructions.bitwise.isZeroInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .AND => inner[possible_opcode] = .{ .execution = instructions.bitwise.andInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .OR => inner[possible_opcode] = .{ .execution = instructions.bitwise.orInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .XOR => inner[possible_opcode] = .{ .execution = instructions.bitwise.xorInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .NOT => inner[possible_opcode] = .{ .execution = instructions.bitwise.notInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .BYTE => inner[possible_opcode] = .{ .execution = instructions.bitwise.byteInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SHL => inner[possible_opcode] = .{ .execution = instructions.bitwise.shiftLeftInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SHR => inner[possible_opcode] = .{ .execution = instructions.bitwise.shiftRightInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .SAR => inner[possible_opcode] = .{ .execution = instructions.bitwise.signedShiftRightInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .KECCAK256 => inner[possible_opcode] = .{ .execution = instructions.system.keccakInstruction(interpreter), .max_stack = maxStack(1024, 2, 1) },
                        .ADDRESS => inner[possible_opcode] = .{ .execution = instructions.system.addressInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .BALANCE => inner[possible_opcode] = .{ .execution = instructions.host.balanceInstruction(interpreter), .max_stack = maxStack(1024, 1, 1) },
                        .ORIGIN => inner[possible_opcode] = .{ .execution = instructions.enviroment.originInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .CALLER => inner[possible_opcode] = .{ .execution = instructions.system.callerInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .CALLVALUE => inner[possible_opcode] = .{ .execution = instructions.system.callValueInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .CALLDATALOAD => inner[possible_opcode] = .{ .execution = instructions.system.callDataLoadInstruction(interpreter), .max_stack = maxStack(1024, 1, 1) },
                        .CALLDATASIZE => inner[possible_opcode] = .{ .execution = instructions.system.callDataSizeInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .CALLDATACOPY => inner[possible_opcode] = .{ .execution = instructions.system.callDataCopyInstruction(interpreter), .max_stack = maxStack(1024, 3, 0) },
                        .CODESIZE => inner[possible_opcode] = .{ .execution = instructions.system.codeSizeInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .CODECOPY => inner[possible_opcode] = .{ .execution = instructions.system.codeCopyInstruction(interpreter), .max_stack = maxStack(1024, 3, 0) },
                        .GASPRICE => inner[possible_opcode] = .{ .execution = instructions.enviroment.gasPriceInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .EXTCODESIZE => inner[possible_opcode] = .{ .execution = instructions.host.extCodeSizeInstruction(interpreter), .max_stack = maxStack(1024, 1, 1) },
                        .EXTCODECOPY => inner[possible_opcode] = .{ .execution = instructions.host.extCodeSizeInstruction(interpreter), .max_stack = maxStack(1024, 4, 0) },
                        .RETURNDATASIZE => inner[possible_opcode] = .{ .execution = instructions.system.returnDataSizeInstruction(interpreter), .max_stack = maxStack(1024, 0, 1) },
                        .RETURNDATACOPY => inner[possible_opcode] = .{ .execution = instructions.system.returnDataCopyInstruction(interpreter), .max_stack = maxStack(1024, 3, 0) },
                        .EXTCODEHASH => inner[possible_opcode] = .{ .execution = instructions.host.extCodeHashInstruction(interpreter), .max_stack = maxStack(1024, 1, 1) },
                    }
                } else {
                    inner[possible_opcode] = .{
                        .execution = instructions.control.unknowInstruction(interpreter),
                        .max_stack = 0,
                    };
                }
            }
        }
    }
};

pub const Operations = struct {
    execution: *const fn (ctx: *Interpreter) anyerror!void,
    max_stack: usize,
};

/// Creates the dup instructions for the instruction table.
pub fn makeDupInstruction(comptime dup_size: u8) *const fn (ctx: *Interpreter) anyerror!void {
    return struct {
        pub fn dup(self: *Interpreter) anyerror!void {
            return instructions.stack.dupInstruction(self, dup_size);
        }
    }.dup;
}
/// Creates the push instructions for the instruction table.
pub fn makePushInstruction(comptime push_size: u8) *const fn (ctx: *Interpreter) anyerror!void {
    return struct {
        pub fn push(self: *Interpreter) anyerror!void {
            return instructions.stack.pushInstruction(self, push_size);
        }
    }.push;
}
/// Creates the swap instructions for the instruction table.
pub fn makeSwapInstruction(comptime swap_size: u8) *const fn (ctx: *Interpreter) anyerror!void {
    return struct {
        pub fn swap(self: *Interpreter) anyerror!void {
            return instructions.stack.swapInstruction(self, swap_size);
        }
    }.swap;
}
/// Callculates the max avaliable size of the stack for the operation to execute.
pub fn maxStack(comptime limit: comptime_int, comptime pop: comptime_int, comptime push: comptime_int) usize {
    return @intCast(limit + pop - push);
}
