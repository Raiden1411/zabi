const actions = @import("../actions.zig");
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const utils = @import("zabi-utils").utils;

const Allocator = std.mem.Allocator;
const CallAction = actions.CallAction;
const CreateScheme = actions.CreateScheme;
const Interpreter = @import("../Interpreter.zig");
const Memory = @import("../memory.zig").Memory;
const PlainHost = @import("../host.zig").PlainHost;

/// Performs call instruction for the interpreter.
/// CALL -> 0xF1
pub fn callInstruction(self: *Interpreter) (error{FailedToLoadAccount} || Interpreter.InstructionErrors)!void {
    const gas_limit = try self.stack.tryPopUnsafe();
    const to = try self.stack.tryPopUnsafe();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const value = try self.stack.tryPopUnsafe();

    if (self.is_static and value != 0) {
        self.status = .call_with_value_not_allowed_in_static_call;
        return;
    }

    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const account = self.host.loadAccount(@bitCast(@as(u160, @intCast(to)))) orelse return error.FailedToLoadAccount;
    var calc_limit = calculateCall(self, value != 0, account.is_cold, account.is_new_account, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    if (value != 0)
        calc_limit +|= gas.CALL_STIPEND;

    self.next_action = .{ .call_action = .{
        .value = .{ .transfer = value },
        .inputs = input,
        .caller = self.contract.target_address,
        .gas_limit = calc_limit,
        .bytecode_address = @bitCast(@as(u160, @intCast(to))),
        .target_address = @bitCast(@as(u160, @intCast(to))),
        .scheme = .call,
        .is_static = self.is_static,
        .return_memory_offset = range,
    } };

    self.status = .call_or_create;
}
/// Performs callcode instruction for the interpreter.
/// CALLCODE -> 0xF2
pub fn callCodeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const gas_limit = try self.stack.tryPopUnsafe();
    const to = try self.stack.tryPopUnsafe();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const value = try self.stack.tryPopUnsafe();

    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const account = self.host.loadAccount(@bitCast(@as(u160, @intCast(to)))) orelse {
        self.status = .invalid;
        return;
    };

    var calc_limit = calculateCall(self, value != 0, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    if (value != 0)
        calc_limit +|= gas.CALL_STIPEND;

    self.next_action = .{ .call_action = .{
        .value = .{ .transfer = value },
        .inputs = input,
        .caller = self.contract.target_address,
        .gas_limit = calc_limit,
        .bytecode_address = self.contract.target_address,
        .target_address = @bitCast(@as(u160, @intCast(to))),
        .scheme = .callcode,
        .is_static = self.is_static,
        .return_memory_offset = range,
    } };

    self.status = .call_or_create;
}
/// Performs create instruction for the interpreter.
/// CREATE -> 0xF0 and CREATE2 -> 0xF5
pub fn createInstruction(self: *Interpreter, is_create_2: bool) (error{ InstructionNotEnabled, Overflow } || Memory.Error || Interpreter.InstructionErrors)!void {
    std.debug.assert(!self.is_static); // Requires non static call.

    if (is_create_2 and !self.spec.enabled(.PETERSBURG))
        return error.InstructionNotEnabled;

    const value = try self.stack.tryPopUnsafe();
    const code_offset = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const buffer = try self.allocator.alloc(u8, len);

    if (length != 0) {
        if (self.spec.enabled(.SHANGHAI)) {
            const max_code_size: usize = blk: {
                if (self.host.getEnviroment().config.limit_contract_size) |limit_size| {
                    break :blk limit_size *| 2;
                }

                break :blk 0x600 * 2;
            };

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
            const salt = try self.stack.tryPopUnsafe();
            const cost = gas.calculateCreate2Cost(len);
            try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

            break :blk .{ .create2 = salt };
        }
        try self.gas_tracker.updateTracker(gas.CREATE);

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
    if (!self.spec.enabled(.HOMESTEAD))
        return error.InstructionNotEnabled;

    const gas_limit = try self.stack.tryPopUnsafe();
    const to = try self.stack.tryPopUnsafe();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const account = self.host.loadAccount(@bitCast(@as(u160, @intCast(to)))) orelse {
        self.status = .invalid;
        return;
    };

    const calc_limit = calculateCall(self, false, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    self.next_action = .{ .call_action = .{
        .value = .{ .limbo = self.contract.value },
        .inputs = input,
        .caller = self.contract.caller,
        .gas_limit = calc_limit,
        .bytecode_address = @bitCast(@as(u160, @intCast(to))),
        .target_address = self.contract.target_address,
        .scheme = .delegate,
        .is_static = self.is_static,
        .return_memory_offset = range,
    } };

    self.status = .call_or_create;
}
/// Performs staticcall instruction for the interpreter.
/// STATICCALL -> 0xFA
pub fn staticCallInstruction(self: *Interpreter) (error{InstructionNotEnabled} || Interpreter.InstructionErrors)!void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    const gas_limit = try self.stack.tryPopUnsafe();
    const to = try self.stack.tryPopUnsafe();

    const limit = std.math.cast(u64, gas_limit) orelse std.math.maxInt(u64);
    const input, const range = getMemoryInputsAndRanges(self) catch return;

    const account = self.host.loadAccount(@bitCast(@as(u160, @intCast(to)))) orelse {
        self.status = .invalid;
        return;
    };

    const calc_limit = calculateCall(self, false, account.is_cold, false, limit) orelse return;

    try self.gas_tracker.updateTracker(calc_limit);

    self.next_action = .{ .call_action = .{
        .value = .{ .transfer = 0 },
        .inputs = input,
        .caller = self.contract.target_address,
        .gas_limit = calc_limit,
        .bytecode_address = @bitCast(@as(u160, @intCast(to))),
        .target_address = @bitCast(@as(u160, @intCast(to))),
        .scheme = .static,
        .is_static = true,
        .return_memory_offset = range,
    } };

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
pub fn getMemoryInputsAndRanges(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { []u8, struct { u64, u64 } } {
    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();
    const third = try self.stack.tryPopUnsafe();
    const fourth = try self.stack.tryPopUnsafe();

    const offset, const len = try resizeMemoryAndGetRange(self, first, second);

    const buffer = try self.allocator.alloc(u8, len);
    errdefer self.allocator.free(buffer);

    if (offset != 0 and len != 0)
        @memcpy(buffer, self.memory.getSlice()[offset .. offset + len]);

    const result = try resizeMemoryAndGetRange(self, third, fourth);

    return .{ buffer, result };
}
/// Resizes the memory as gets the offset ranges.
pub fn resizeMemoryAndGetRange(self: *Interpreter, offset: u256, len: u256) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!struct { u64, u64 } {
    const length = std.math.cast(u64, len) orelse std.math.maxInt(u64);
    const offset_len = std.math.cast(u64, offset) orelse return error.Overflow;

    const end: u64 = blk: {
        if (len == 0)
            break :blk comptime std.math.maxInt(u64);

        try self.resize(length +| offset_len);

        break :blk offset_len;
    };

    return .{ end, length };
}
