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
    /// No action for the interpreter to take.
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
memory: Memory,
/// The next interpreter action.
next_action: InterpreterActions,
/// The interpreter's counter.
program_counter: u64,
/// The buffer containing the return data
return_data: []u8,
/// The spec for this interpreter.
spec: SpecId,
/// The stack of the interpreter with 1024 max size.
stack: Stack(u256),
/// The current interpreter status.
status: InterpreterStatus,

/// Sets the interpreter to it's expected initial state.
pub fn init(self: *Interpreter, allocator: Allocator, contract_instance: Contract, gas_limit: u64, is_static: bool, evm_host: Host, spec_id: SpecId) !void {
    const bytecode = try allocator.dupe(u8, contract_instance.bytecode);
    errdefer allocator.free(bytecode);

    self.* = .{
        .allocator = allocator,
        .code = bytecode,
        .contract = contract_instance,
        .memory = Memory.initEmpty(allocator, null),
        .gas_tracker = GasTracker.init(gas_limit),
        .host = evm_host,
        .is_static = is_static,
        .next_action = .no_action,
        .program_counter = 0,
        .spec = spec_id,
        .stack = try Stack(u256).initWithCapacity(allocator, 1024),
        .status = .running,
        .return_data = &[0]u8{},
    };
}
/// Clear memory and destroy's any created pointers.
pub fn deinit(self: *Interpreter) void {
    self.stack.deinit();
    self.memory.deinit();

    self.allocator.free(self.code);

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
