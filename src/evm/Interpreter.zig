const actions = @import("actions.zig");
const contract = @import("contract.zig");
const gas = @import("gas_tracker.zig");
const host = @import("host.zig");
const mem = @import("memory.zig");
const opcode = @import("opcodes.zig");
const spec = @import("specification.zig");
const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const CallAction = actions.CallAction;
const Contract = contract.Contract;
const CreateAction = actions.CreateAction;
const GasTracker = gas.GasTracker;
const InstructionTable = opcode.InstructionTable;
const Host = host.Host;
const Memory = mem.Memory;
const PlainHost = host.PlainHost;
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

    /// Clears any memory with the associated action.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .call_action => |call| allocator.free(call.inputs.ptr[0..call.inputs.len]),
            .create_action => |create| allocator.free(create.init_code.ptr[0..create.init_code.len]),
            .return_action => |ret| allocator.free(ret.output.ptr[0..ret.output.len]),
            .no_action => {},
        }
    }
};

/// The status of execution for the interpreter.
pub const InterpreterStatus = enum {
    call_or_create,
    call_with_value_not_allowed_in_static_call,
    create_code_size_limit,
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

/// Set of default options that the interperter needs
/// for it to be able to run.
pub const InterpreterInitOptions = struct {
    /// Maximum amount of gas available to perform the operations
    gas_limit: u64 = 30_000_000,
    /// Tells the interperter if it's going to run as a static call
    is_static: bool = false,
    /// Sets the interperter spec based on the hardforks.
    spec_id: SpecId = .LATEST,
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
/// The spec for this interpreter.
spec: SpecId,
/// The stack of the interpreter with 1024 max size.
stack: Stack(u256),
/// The current interpreter status.
status: InterpreterStatus,
/// The buffer containing the return data
return_data: []u8,

/// Sets the interpreter to it's expected initial state.
/// Copy's the contract's bytecode independent of it's state.
pub fn init(self: *Interpreter, allocator: Allocator, contract_instance: Contract, evm_host: Host, opts: InterpreterInitOptions) !void {
    const bytecode = try allocator.dupe(u8, contract_instance.bytecode.getCodeBytes());
    errdefer allocator.free(bytecode);

    self.* = .{
        .allocator = allocator,
        .code = bytecode,
        .contract = contract_instance,
        .memory = Memory.initEmpty(allocator, null),
        .gas_tracker = GasTracker.init(opts.gas_limit),
        .host = evm_host,
        .is_static = opts.is_static,
        .next_action = .no_action,
        .program_counter = 0,
        .spec = opts.spec_id,
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
    self.allocator.free(self.return_data.ptr[0..self.return_data.len]);
}
/// Moves the `program_counter` by one.
pub fn advanceProgramCounter(self: *Interpreter) void {
    self.program_counter += 1;
}
/// Runs a single instruction based on the `program_counter`
/// position and the associated bytecode. Doesn't move the counter.
pub fn runInstruction(self: *Interpreter) !void {
    const opcode_bit = self.code[self.program_counter];

    const operation = opcode.instruction_table.getInstruction(opcode_bit);

    if (self.stack.stackHeight() > operation.max_stack)
        return error.StackOverflow;

    try operation.execution(self);
}
/// Runs the associated contract bytecode.
/// Depending on the interperter final `status` this can return errors.
/// The bytecode that will get run will be padded with `STOP` instructions
/// at the end to make sure that we don't have index out of bounds panics.
pub fn run(self: *Interpreter) !InterpreterActions {
    while (self.status == .running) : (self.advanceProgramCounter()) {
        try self.runInstruction();
    }

    // Handles the different status of the interperter after it's finished
    switch (self.status) {
        .opcode_not_found => return error.OpcodeNotFound,
        .call_with_value_not_allowed_in_static_call => return error.CallWithValueNotAllowedInStaticCall,
        .invalid => return error.InvalidInstructionOpcode,
        .reverted => return error.InterpreterReverted,
        .create_code_size_limit => return error.CreateCodeSizeLimit,
        .invalid_offset => return error.InvalidOffset,
        .invalid_jump => return error.InvalidJump,
        else => {},
    }

    if (self.next_action != .no_action)
        return self.next_action;

    return .{ .return_action = .{
        .gas = self.gas_tracker,
        .output = &.{},
        .result = self.status,
    } };
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
