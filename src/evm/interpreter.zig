const arithmetic = @import("instructions/arithmetic.zig");
const bitwise = @import("instructions/bitwise.zig");
const contract = @import("contract.zig");
const gas = @import("gas_tracker.zig");
const mem = @import("memory.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Contract = contract.Contract;
const GasTracker = gas.GasTracker;
const Memory = mem.Memory;
const Opcodes = @import("opcodes.zig").Opcodes;
const Stack = @import("../utils/stack.zig").Stack;

const Interpreter = @This();

pub const InterpreterStatus = enum {
    Ended,
    Running,
    Returned,
    Reverted,
    Stopped,
};

/// Interpreter allocator used to manage memory.
allocator: Allocator,
/// compiled bytecode that will get ran.
code: []u8,
/// The contract associated to this interpreter.
contract: Contract,
/// Tracker for used gas by the interpreter.
gas_tracker: GasTracker,
/// the interpreter's counter.
program_counter: u64,
/// The stack of the interpreter with 1024 max size.
stack: *Stack(u256),
/// The memory used by this interpreter.
memory: *Memory,
/// The current interpreter status.
status: InterpreterStatus,

/// Sets the interpreter to it's expected initial state.
/// `code` is expected to be a hex string of compiled bytecode.
pub fn init(self: *Interpreter, allocator: Allocator, code: []const u8, gas_limit: u64) !void {
    const stack = try allocator.create(Stack(u256));
    errdefer allocator.destroy(stack);

    stack.* = try Stack(u256).initWithCapacity(allocator, 1024);

    const bytecode = if (std.mem.startsWith(u8, code, "0x")) code[2..] else code;
    const buffer = try allocator.alloc(u8, @divExact(bytecode.len, 2));
    errdefer allocator.free(buffer);

    _ = try std.fmt.hexToBytes(buffer, bytecode);

    self.* = .{
        .allocator = allocator,
        .code = buffer,
        .contract = undefined,
        .gas_tracker = GasTracker.init(gas_limit),
        .program_counter = 0,
        .stack = stack,
        .status = .Running,
    };
}
/// Clear memory and destroy's any created pointers.
pub fn deinit(self: *Interpreter) void {
    self.stack.deinit();

    self.allocator.free(self.code);
    self.allocator.destroy(self.stack);

    self.* = undefined;
}
/// Run a instruction based on the defined opcodes.
pub fn runInstruction(self: *Interpreter) !void {
    if (self.program_counter > self.code.len - 1) {
        self.status = .Ended;
        return;
    }

    const instruction = self.code[self.program_counter];

    const opcode = try Opcodes.toOpcode(instruction);

    switch (opcode) {
        .STOP => self.stopInstruction(),
        .ADD => try arithmetic.addInstruction(self),
        .MUL => try arithmetic.mulInstruction(self),
        .SUB => try arithmetic.subInstruction(self),
        .DIV => try arithmetic.divInstruction(self),
        .SDIV => try arithmetic.signedDivInstruction(self),
        .MOD => try arithmetic.modInstruction(self),
        .SMOD => try arithmetic.signedModInstruction(self),
        .ADDMOD => try arithmetic.modAdditionInstruction(self),
        .MULMOD => try arithmetic.modMultiplicationInstruction(self),
        .EXP => try arithmetic.exponentInstruction(self),
        .SIGNEXTEND => try arithmetic.signedExponentInstruction(self),
        .LT => try bitwise.lowerThanInstruction(self),
        .GT => try bitwise.greaterThanInstruction(self),
        .SLT => try bitwise.signedLowerThanInstruction(self),
        .SGT => try bitwise.signedGreaterThanInstruction(self),
        .EQ => try bitwise.equalInstruction(self),
        .ISZERO => try bitwise.isZeroInstruction(self),
        .AND => try bitwise.andInstruction(self),
        .XOR => try bitwise.xorInstruction(self),
        .OR => try bitwise.orInstruction(self),
        .NOT => try bitwise.notInstruction(self),
        .BYTE => try bitwise.byteInstruction(self),
        .SHL => try bitwise.shiftLeftInstruction(self),
        .SHR => try bitwise.shiftRightInstruction(self),
        .SAR => try bitwise.signedShiftRightInstruction(self),
        else => return error.UnsupportedOpcode,
    }
}

// Opcode instructions
fn stopInstruction(self: *Interpreter) void {
    self.status = .Stopped;
}
