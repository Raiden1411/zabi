const actions = @import("actions.zig");
const arithmetic = @import("instructions/arithmetic.zig");
const bitwise = @import("instructions/bitwise.zig");
const contract = @import("contract.zig");
const gas = @import("gas_tracker.zig");
const host = @import("host.zig");
const mem = @import("memory.zig");
const spec = @import("specification.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const CallAction = actions.CallAction;
const Contract = contract.Contract;
const CreateAction = actions.CreateAction;
const GasTracker = gas.GasTracker;
const Host = host.Host;
const Memory = mem.Memory;
const Opcodes = @import("opcodes.zig").Opcodes;
const ReturnAction = actions.ReturnAction;
const SpecId = spec.SpecId;
const Stack = @import("../utils/stack.zig").Stack;

const Interpreter = @This();

/// The set of next interpreter actions.
pub const InterpreterActions = union(enum) {
    /// Call action.
    call_action: CallAction,
    /// Create action.
    create_action: CreateAction,
    /// Return action.
    return_action: ReturnAction,
    no_action,
};

/// The status of execution for the interpreter.
pub const InterpreterStatus = enum {
    call_or_create,
    call_with_value_not_allowed_in_static_call,
    invalid,
    invalid_jump,
    invalid_offset,
    opcode_not_found,
    returned,
    reverted,
    running,
    self_destructed,
    stopped,
};

/// Interpreter allocator used to manage memory.
allocator: Allocator,
/// Compiled bytecode that will get ran.
code: []u8,
/// The contract associated to this interpreter.
contract: Contract,
/// Tracker for used gas by the interpreter.
gas_tracker: GasTracker,
/// The host enviroment for this interpreter.
host: Host,
/// Is the interperter being ran in a static call.
is_static: bool,
/// The memory used by this interpreter.
memory: *Memory,
/// The next interpreter action.
next_action: InterpreterActions,
/// The interpreter's counter.
program_counter: u64,
/// The buffer containing the return data
return_data: []u8,
/// The spec for this interpreter.
spec: SpecId,
/// The stack of the interpreter with 1024 max size.
stack: *Stack(u256),
/// The current interpreter status.
status: InterpreterStatus,

/// Sets the interpreter to it's expected initial state.
/// `code` is expected to be a hex string of compiled bytecode.
pub fn init(self: *Interpreter, allocator: Allocator, contract_instance: Contract, gas_limit: u64, is_static: bool, evm_host: Host) !void {
    const stack = try allocator.create(Stack(u256));
    errdefer allocator.destroy(stack);

    stack.* = try Stack(u256).initWithCapacity(allocator, 1024);

    const memory = try allocator.create(Memory);
    errdefer allocator.destroy(memory);

    memory.* = Memory.initEmpty(allocator, null);

    const bytecode = try allocator.dupe(u8, contract_instance.bytecode);
    errdefer allocator.free(bytecode);

    self.* = .{
        .allocator = allocator,
        .code = bytecode,
        .contract = undefined,
        .gas_tracker = GasTracker.init(gas_limit),
        .host = evm_host,
        .is_static = is_static,
        .program_counter = 0,
        .stack = stack,
        .status = .Running,
    };
}
/// Clear memory and destroy's any created pointers.
pub fn deinit(self: *Interpreter) void {
    self.stack.deinit();
    self.memory.deinit();

    self.allocator.free(self.code);
    self.allocator.destroy(self.stack);
    self.allocator.destroy(self.memory);

    self.* = undefined;
}
/// Resizes the inner memory size. Adds gas expansion cost to
/// the gas tracker.
pub fn resize(self: *Interpreter, new_size: u64) !void {
    const count = mem.availableWords(new_size);
    const mem_cost = gas.calculateMemoryCost(count);
    const current_cost = gas.calculateMemoryCost(mem.availableWords(self.memory.getCurrentMemorySize()));
    const cost = mem_cost - current_cost;

    try self.gas_tracker.updateTracker(cost);
    return self.memory.resize(count * 32);
}
/// Run a instruction based on the defined opcodes.
pub fn runInstruction(self: *Interpreter) !void {
    if (self.program_counter > self.code.len - 1) {
        self.status = .invalid_offset;
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
