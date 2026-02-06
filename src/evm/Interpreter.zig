const actions = @import("actions.zig");
const constants = zabi_utils.constants;
const contract_type = @import("contract.zig");
const gas = @import("gas_tracker.zig");
const host_type = @import("host.zig");
const mem = @import("memory.zig");
const opcode = @import("opcodes.zig");
const specid = @import("specification.zig");
const std = @import("std");
const testing = std.testing;
const utils = zabi_utils.utils;
const zabi_utils = @import("zabi-utils");

const Allocator = std.mem.Allocator;
const CallAction = actions.CallAction;
const Contract = contract_type.Contract;
const CreateAction = actions.CreateAction;
const GasTracker = gas.GasTracker;
const Host = host_type.Host;
const InstructionTable = opcode.InstructionTable;
const Memory = mem.Memory;
const Opcodes = opcode.Opcodes;
const PlainHost = host_type.PlainHost;
const ReturnAction = actions.ReturnAction;
const SpecId = specid.SpecId;
const Stack = zabi_utils.stack.BoundedStack(1024);

const Interpreter = @This();

/// Set of common errors when running indivual instructions.
pub const InstructionErrors = Allocator.Error || error{ StackUnderflow, StackOverflow, Overflow, FailedToLoadAccount } || GasTracker.Error;

/// Set of all possible errors of interpreter instructions.
pub const AllInstructionErrors = InstructionErrors || Memory.Error || error{
    UnexpectedError,
    InvalidJump,
    InstructionNotEnabled,
};

/// Set of possible errors when running the interpreter.
pub const InterpreterRunErrors = AllInstructionErrors || error{
    OpcodeNotFound,
    InvalidInstructionOpcode,
    InterpreterReverted,
    InvalidOffset,
    CallWithValueNotAllowedInStaticCall,
    CreateCodeSizeLimit,
};

/// Set of possible errors that can be returned depending on the interpreter's current state.
pub const InterpreterStatusErrors = error{
    OpcodeNotFound,
    CallWithValueNotAllowedInStaticCall,
    InvalidInstructionOpcode,
    InterpreterReverted,
    CreateCodeSizeLimit,
    InvalidOffset,
    InvalidJump,
};

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
contract: *const Contract,
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
program_counter: usize,
/// The spec for this interpreter.
spec: SpecId,
/// The stack of the interpreter with 1024 max size.
stack: Stack,
/// The current interpreter status.
status: InterpreterStatus,
/// The buffer containing the return data
return_data: []u8,

/// Sets the interpreter to it's expected initial state.
///
/// Copy's the contract's bytecode independent of it's state.
///
/// **Example**
/// ```zig
/// const contract_instance = try Contract.init(
///     testing.allocator,
///     &.{},
///     .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }) },
///     null,
///     0,
///     [_]u8{1} ** 20,
///     [_]u8{0} ** 20,
/// );
/// defer contract_instance.deinit(testing.allocator);
///
/// var plain: PlainHost = undefined;
/// defer plain.deinit();
///
/// plain.init(testing.allocator);
///
/// var interpreter: Interpreter = undefined;
/// defer interpreter.deinit();
///
/// try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});
/// ```
pub fn init(
    self: *Interpreter,
    allocator: Allocator,
    contract_instance: *const Contract,
    evm_host: Host,
    opts: InterpreterInitOptions,
) Allocator.Error!void {
    self.* = .{
        .allocator = allocator,
        .code = contract_instance.bytecode.getCodeBytes(),
        .contract = contract_instance,
        .memory = try Memory.initWithDefaultCapacity(allocator, null),
        .gas_tracker = GasTracker.init(opts.gas_limit),
        .host = evm_host,
        .is_static = opts.is_static,
        .next_action = .no_action,
        .program_counter = 0,
        .spec = opts.spec_id,
        .stack = .{ .len = 0 },
        .status = .running,
        .return_data = &[0]u8{},
    };
}

/// Clear memory and destroy's any created pointers.
pub fn deinit(self: *Interpreter) void {
    self.memory.deinit();

    self.allocator.free(self.return_data.ptr[0..self.return_data.len]);
}

/// Moves the `program_counter` by one.
pub fn advanceProgramCounter(self: *Interpreter) void {
    self.program_counter += 1;
}

/// Runs the associated contract bytecode.
///
/// Depending on the interperter final `status` this can return errors.\
/// The bytecode that will get run will be padded with `STOP` instructions
/// at the end to make sure that we don't have index out of bounds panics.
///
/// **Example**
/// ```zig
/// const contract_instance = try Contract.init(
///     testing.allocator,
///     &.{},
///     .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01 }) },
///     null,
///     0,
///     [_]u8{1} ** 20,
///     [_]u8{0} ** 20,
/// );
/// defer contract_instance.deinit(testing.allocator);
///
/// var plain: PlainHost = undefined;
/// defer plain.deinit();
///
/// plain.init(testing.allocator);
///
/// var interpreter: Interpreter = undefined;
/// defer interpreter.deinit();
///
/// try interpreter.init(testing.allocator, contract_instance, plain.host(), .{});
///
/// const result = try interpreter.run();
/// defer result.deinit(testing.allocator);
/// ```
pub fn run(self: *Interpreter) (AllInstructionErrors || InterpreterStatusErrors)!InterpreterActions {
    while (self.status == .running) {
        const op = self.code[self.program_counter];
        self.advanceProgramCounter();

        const operation = opcode.instruction_table.getInstruction(op);
        const stack_height = self.stack.stackHeight();

        if (stack_height < operation.min_stack) {
            @branchHint(.unlikely);
            return error.StackUnderflow;
        }

        if (stack_height > operation.max_stack) {
            @branchHint(.unlikely);
            return error.StackOverflow;
        }

        switch (op) {
            @intFromEnum(Opcodes.JUMP) => {
                try self.gas_tracker.updateTracker(constants.MID_STEP);

                const target = self.stack.pop();
                const target_usize = std.math.cast(usize, target) orelse {
                    @branchHint(.unlikely);
                    return error.InvalidJump;
                };

                if (!self.contract.isValidJump(target_usize)) {
                    @branchHint(.unlikely);
                    return error.InvalidJump;
                }

                self.program_counter = target_usize;
            },
            @intFromEnum(Opcodes.JUMPI) => {
                try self.gas_tracker.updateTracker(constants.MID_STEP);

                const target = self.stack.pop();
                const condition = self.stack.pop();

                if (condition != 0) {
                    const target_usize = std.math.cast(usize, target) orelse {
                        @branchHint(.unlikely);
                        return error.InvalidJump;
                    };

                    if (!self.contract.isValidJump(target_usize)) {
                        @branchHint(.unlikely);
                        return error.InvalidJump;
                    }

                    self.program_counter = target_usize;
                }
            },
            @intFromEnum(Opcodes.JUMPDEST) => try self.gas_tracker.updateTracker(constants.JUMPDEST),
            @intFromEnum(Opcodes.POP) => {
                try self.gas_tracker.updateTracker(constants.QUICK_STEP);
                _ = self.stack.pop();
            },
            @intFromEnum(Opcodes.PUSH0) => {
                if (!self.spec.enabled(.SHANGHAI)) {
                    @branchHint(.unlikely);
                    return error.OpcodeNotFound;
                }

                try self.gas_tracker.updateTracker(constants.QUICK_STEP);
                self.stack.appendAssumeCapacity(0);
            },
            @intFromEnum(Opcodes.PUSH1)...@intFromEnum(Opcodes.PUSH32) => |push_op| {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const size: usize = push_op - 0x5f;
                const end = @min(self.program_counter + size, self.code.len);

                var value: u256 = 0;
                for (self.code[self.program_counter..end]) |byte|
                    value = (value << 8) | byte;

                self.stack.appendAssumeCapacity(value);
                self.program_counter += size;
            },
            @intFromEnum(Opcodes.DUP1)...@intFromEnum(Opcodes.DUP16) => |dup_op| {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
                const position: usize = dup_op - 0x7f;

                self.stack.dup(position);
            },
            @intFromEnum(Opcodes.SWAP1)...@intFromEnum(Opcodes.SWAP16) => |swap_op| {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);
                const position: usize = swap_op - 0x8f;

                self.stack.swapToTop(position);
            },
            @intFromEnum(Opcodes.ADD) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a +% b.*;
            },
            @intFromEnum(Opcodes.SUB) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a -% b.*;
            },
            @intFromEnum(Opcodes.MUL) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a *% b.*;
            },
            @intFromEnum(Opcodes.DIV) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                if (b.* == 0) {
                    @branchHint(.cold);
                    continue;
                }

                b.* = a / b.*;
            },
            @intFromEnum(Opcodes.SDIV) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                if (b.* == 0) {
                    @branchHint(.unlikely);
                    continue;
                }

                const casted_first: i256 = @bitCast(a);
                const casted_second: i256 = @bitCast(b.*);

                const sign: u256 = @bitCast((casted_first ^ casted_second) >> 255);

                const abs_n = (casted_first ^ (casted_first >> 255)) -% (casted_first >> 255);
                const abs_d = (casted_second ^ (casted_second >> 255)) -% (casted_second >> 255);

                const abs_n_u: u256 = @bitCast(abs_n);
                const abs_d_u: u256 = @bitCast(abs_d);

                const res = blk: {
                    if (utils.fitsInU128(abs_n_u) and utils.fitsInU128(abs_d_u)) {
                        @branchHint(.likely);
                        break :blk @as(u128, @truncate(abs_n_u)) / @as(u128, @truncate(abs_d_u));
                    } else break :blk abs_n_u / abs_d_u;
                };

                b.* = (res ^ sign) -% sign;
            },
            @intFromEnum(Opcodes.MOD) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                if (b.* == 0) {
                    @branchHint(.unlikely);
                    continue;
                }

                b.* = @mod(a, b.*);
            },
            @intFromEnum(Opcodes.ISZERO) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.peek();
                a.* = @intFromBool(a.* == 0);
            },
            @intFromEnum(Opcodes.LT) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = @intFromBool(a < b.*);
            },
            @intFromEnum(Opcodes.GT) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = @intFromBool(a > b.*);
            },
            @intFromEnum(Opcodes.SLT) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = @intFromBool(@as(i256, @bitCast(a)) < @as(i256, @bitCast(b.*)));
            },
            @intFromEnum(Opcodes.SGT) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = @intFromBool(@as(i256, @bitCast(a)) > @as(i256, @bitCast(b.*)));
            },
            @intFromEnum(Opcodes.EQ) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = @intFromBool(a == b.*);
            },
            @intFromEnum(Opcodes.AND) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a & b.*;
            },
            @intFromEnum(Opcodes.OR) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a | b.*;
            },
            @intFromEnum(Opcodes.XOR) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.pop();
                const b = self.stack.peek();

                b.* = a ^ b.*;
            },
            @intFromEnum(Opcodes.NOT) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const a = self.stack.peek();
                a.* = ~a.*;
            },
            @intFromEnum(Opcodes.SHL) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const shift = self.stack.pop();
                const value = self.stack.peek();

                value.* = std.math.shl(u256, value.*, shift);
            },
            @intFromEnum(Opcodes.SHR) => {
                try self.gas_tracker.updateTracker(constants.FAST_STEP);

                const shift = self.stack.pop();
                const value = self.stack.peek();

                value.* = std.math.shr(u256, value.*, shift);
            },
            @intFromEnum(Opcodes.BYTE) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const i = self.stack.pop();
                const x = self.stack.peek();

                if (i >= 32) {
                    @branchHint(.unlikely);
                    x.* = 0;
                    continue;
                }

                x.* = (x.* >> @intCast((31 - i) * 8)) & 0xff;
            },
            @intFromEnum(Opcodes.MLOAD) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const offset = self.stack.peek();
                const as_usize = std.math.cast(usize, offset.*) orelse {
                    @branchHint(.unlikely);
                    return error.InvalidOffset;
                };

                const new_size = as_usize +| 32;
                try self.resize(new_size);

                offset.* = self.memory.wordToInt(as_usize);
            },
            @intFromEnum(Opcodes.MSTORE) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const offset = self.stack.pop();
                const value = self.stack.pop();
                const as_usize = std.math.cast(usize, offset) orelse {
                    @branchHint(.unlikely);
                    return error.Overflow;
                };

                const new_size = as_usize +| 32;
                try self.resize(new_size);

                self.memory.writeInt(as_usize, value);
            },
            @intFromEnum(Opcodes.MSTORE8) => {
                try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

                const offset = self.stack.pop();
                const value = self.stack.pop();
                const as_usize = std.math.cast(usize, offset) orelse {
                    @branchHint(.unlikely);
                    return error.Overflow;
                };

                const new_size = as_usize +| 1;
                try self.resize(new_size);

                self.memory.writeByte(as_usize, @truncate(value));
            },
            @intFromEnum(Opcodes.MSIZE) => {
                try self.gas_tracker.updateTracker(constants.QUICK_STEP);
                self.stack.appendAssumeCapacity(self.memory.getCurrentMemorySize());
            },
            else => try operation.execution(self),
        }
    }

    // Handle the different status of the interpreter after it's finished
    switch (self.status) {
        .running => unreachable,
        .opcode_not_found => return error.OpcodeNotFound,
        .call_with_value_not_allowed_in_static_call => return error.CallWithValueNotAllowedInStaticCall,
        .invalid => return error.InvalidInstructionOpcode,
        .reverted => return error.InterpreterReverted,
        .create_code_size_limit => return error.CreateCodeSizeLimit,
        .invalid_offset => return error.InvalidOffset,
        inline else => |status| switch (self.next_action) {
            .return_action,
            .call_action,
            .create_action,
            => {
                const action = self.next_action;
                self.next_action = .no_action;

                return action;
            },
            .no_action,
            => return .{
                .return_action = .{
                    .gas = self.gas_tracker,
                    .output = try self.allocator.dupe(u8, self.return_data),
                    .result = status,
                },
            },
        },
    }
}

/// Resizes the inner memory size. Adds gas expansion cost to the gas tracker.
pub fn resize(
    self: *Interpreter,
    new_size: usize,
) (Allocator.Error || GasTracker.Error || Memory.Error)!void {
    if (new_size > self.memory.getCurrentMemorySize()) {
        const count = mem.availableWords(new_size);
        const mem_cost = gas.calculateMemoryCost(count);
        const current_cost = gas.calculateMemoryCost(mem.availableWords(self.memory.getCurrentMemorySize()));
        const cost = mem_cost - current_cost;

        try self.gas_tracker.updateTracker(cost);
        return self.memory.resize(count * 32);
    }
}
