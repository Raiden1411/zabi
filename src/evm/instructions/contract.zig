const actions = @import("../actions.zig");
const constants = @import("zabi-utils").constants;
const fork_rules = @import("../fork_rules.zig");
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const utils = @import("zabi-utils").utils;
const types = @import("zabi-types").ethereum;

const Allocator = std.mem.Allocator;
const Address = types.Address;
const CallAction = actions.CallAction;
const CreateScheme = actions.CreateScheme;
const GatedOpcode = fork_rules.GatedOpcode;
const Interpreter = @import("../Interpreter.zig");
const Memory = @import("../memory.zig").Memory;
const PlainHost = @import("../host.zig").PlainHost;

/// Performs call instruction for the interpreter.
/// CALL -> 0xF1
pub fn callInstruction(self: *Interpreter) (error{FailedToLoadAccount} || Interpreter.InstructionErrors)!void {
    const gas_limit = self.stack.pop();
    const to = self.stack.pop();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const value = self.stack.pop();

    if (self.is_static and value != 0) {
        self.status = .call_with_value_not_allowed_in_static_call;
        return;
    }

    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const to_address: Address = @bitCast(std.mem.nativeToBig(u160, @intCast(to)));
    const account = self.host.loadAccount(to_address) orelse return error.FailedToLoadAccount;
    var calc_limit = calculateCall(self, value != 0, account.is_cold, account.is_new_account, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    if (value != 0)
        calc_limit +|= constants.CALL_STIPEND;

    self.next_action = .{
        .call_action = .{
            .value = .{ .transfer = value },
            .inputs = input,
            .caller = self.contract.target_address,
            .gas_limit = calc_limit,
            .bytecode_address = to_address,
            .target_address = to_address,
            .scheme = .call,
            .is_static = self.is_static,
            .return_memory_offset = range,
        },
    };

    self.status = .call_or_create;
}

/// Performs callcode instruction for the interpreter.
/// CALLCODE -> 0xF2
pub fn callCodeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const gas_limit = self.stack.pop();
    const to = self.stack.pop();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const value = self.stack.pop();

    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const to_address: Address = @bitCast(std.mem.nativeToBig(u160, @intCast(to)));
    const account = self.host.loadAccount(to_address) orelse {
        self.status = .invalid;
        return;
    };

    var calc_limit = calculateCall(self, value != 0, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    if (value != 0)
        calc_limit +|= constants.CALL_STIPEND;

    self.next_action = .{
        .call_action = .{
            .value = .{ .transfer = value },
            .inputs = input,
            .caller = self.contract.target_address,
            .gas_limit = calc_limit,
            .bytecode_address = self.contract.target_address,
            .target_address = to_address,
            .scheme = .callcode,
            .is_static = self.is_static,
            .return_memory_offset = range,
        },
    };

    self.status = .call_or_create;
}

/// Performs create instruction for the interpreter.
/// CREATE -> 0xF0 and CREATE2 -> 0xF5
pub inline fn createInstruction(self: *Interpreter, is_create_2: bool) (error{ InstructionNotEnabled, Overflow } || Memory.Error || Interpreter.InstructionErrors)!void {
    std.debug.assert(!self.is_static); // Requires non static call.

    if (is_create_2 and !GatedOpcode.CREATE2.isEnabled(self.spec)) {
        @branchHint(.cold);
        return error.InstructionNotEnabled;
    }

    const value = self.stack.pop();
    const code_offset = self.stack.pop();
    const length = self.stack.pop();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const buffer = try self.allocator.alloc(u8, len);

    if (length != 0) {
        if (self.spec.enabled(.SHANGHAI)) {
            const max_code_size: usize =
                self.host.getEnviroment().config.limit_contract_size *| 2;

            if (length > max_code_size) {
                self.status = .create_code_size_limit;
                return;
            }

            const cost = gas.calculateCreateCost(len);
            try self.gas_tracker.updateTracker(cost);
        }

        const code_offset_len = std.math.cast(usize, code_offset) orelse return error.Overflow;

        try self.resize(len +| code_offset_len);
        @memcpy(buffer, self.memory.getSlice()[code_offset_len .. code_offset_len + len]);
    }

    const scheme: CreateScheme = blk: {
        if (is_create_2) {
            const salt = self.stack.pop();
            const cost = gas.calculateCreate2Cost(len);
            try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

            break :blk .{ .create2 = salt };
        }
        try self.gas_tracker.updateTracker(constants.CREATE);

        break :blk .{ .create = {} };
    };

    var limit = self.gas_tracker.availableGas();

    if (self.spec.enabled(.TANGERINE))
        limit -= @divFloor(limit, 64);

    try self.gas_tracker.updateTracker(limit);

    self.next_action = .{
        .create_action = .{
            .value = value,
            .init_code = buffer,
            .caller = self.contract.target_address,
            .gas_limit = limit,
            .scheme = scheme,
        },
    };

    self.status = .call_or_create;
}

/// Performs delegatecall instruction for the interpreter.
/// DELEGATECALL -> 0xF4
pub fn delegateCallInstruction(self: *Interpreter) (error{InstructionNotEnabled} || Interpreter.InstructionErrors)!void {
    if (!GatedOpcode.DELEGATECALL.isEnabled(self.spec)) {
        @branchHint(.cold);
        return error.InstructionNotEnabled;
    }

    const gas_limit = self.stack.pop();
    const to = self.stack.pop();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const to_address: Address = @bitCast(std.mem.nativeToBig(u160, @intCast(to)));
    const account = self.host.loadAccount(to_address) orelse {
        self.status = .invalid;
        return;
    };

    const calc_limit = calculateCall(self, false, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    self.next_action = .{
        .call_action = .{
            .value = .{ .limbo = self.contract.value },
            .inputs = input,
            .caller = self.contract.caller,
            .gas_limit = calc_limit,
            .bytecode_address = to_address,
            .target_address = self.contract.target_address,
            .scheme = .delegate,
            .is_static = self.is_static,
            .return_memory_offset = range,
        },
    };

    self.status = .call_or_create;
}

/// Performs staticcall instruction for the interpreter.
/// STATICCALL -> 0xFA
pub fn staticCallInstruction(self: *Interpreter) (error{InstructionNotEnabled} || Interpreter.InstructionErrors)!void {
    if (!GatedOpcode.STATICCALL.isEnabled(self.spec)) {
        @branchHint(.cold);
        return error.InstructionNotEnabled;
    }

    const gas_limit = self.stack.pop();
    const to = self.stack.pop();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const to_address: Address = @bitCast(std.mem.nativeToBig(u160, @intCast(to)));
    const account = self.host.loadAccount(to_address) orelse {
        self.status = .invalid;
        return;
    };

    const calc_limit = calculateCall(self, false, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    self.next_action = .{
        .call_action = .{
            .value = .{ .transfer = 0 },
            .inputs = input,
            .caller = self.contract.target_address,
            .gas_limit = calc_limit,
            .bytecode_address = to_address,
            .target_address = to_address,
            .scheme = .static,
            .is_static = true,
            .return_memory_offset = range,
        },
    };

    self.status = .call_or_create;
}

// Helpers

/// Calculates the gas cost for a `CALL` opcode.
/// Habides by EIP-150 where gas gets calculated as the min of available - (available / 64) or `local_gas_limit`
pub inline fn calculateCall(self: *Interpreter, values_transfered: bool, is_cold: bool, new_account: bool, local_gas_limit: u64) ?u64 {
    const cost = gas.calculateCallCost(self.spec, values_transfered, is_cold, new_account);

    self.gas_tracker.updateTracker(cost) catch return null;

    const limit = blk: {
        if (self.spec.enabled(.TANGERINE)) {
            const available = self.gas_tracker.availableGas();

            break :blk @min(available - @divFloor(available, 64), local_gas_limit);
        }
        break :blk local_gas_limit;
    };

    return limit;
}

/// Gets the memory slice and the ranges used to grab it.
/// This also resizes the interpreter's memory.
pub fn getMemoryInputsAndRanges(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { []u8, struct { usize, usize } } {
    const first = self.stack.pop();
    const second = self.stack.pop();
    const third = self.stack.pop();
    const fourth = self.stack.pop();

    const offset, const len = try resizeMemoryAndGetRange(self, first, second);

    const buffer = try self.allocator.alloc(u8, @intCast(len));
    errdefer self.allocator.free(buffer);

    if (len != 0)
        @memcpy(buffer, self.memory.getSlice()[offset .. offset + len]);

    const result = try resizeMemoryAndGetRange(self, third, fourth);

    return .{ buffer, result };
}

/// Resizes the memory as gets the offset ranges.
pub fn resizeMemoryAndGetRange(
    self: *Interpreter,
    offset: u256,
    len: u256,
) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { usize, usize } {
    const length = std.math.cast(usize, len) orelse std.math.maxInt(usize);
    const offset_len = std.math.cast(usize, offset) orelse return error.Overflow;

    const end: usize = blk: {
        if (len == 0)
            break :blk comptime std.math.maxInt(usize);

        try self.resize(length +| offset_len);

        break :blk offset_len;
    };

    return .{ end, length };
}
