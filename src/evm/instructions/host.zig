const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const host = @import("../host.zig");
const log_types = @import("zabi-types").log;
const std = @import("std");
const utils = @import("zabi-utils").utils;

const Interpreter = @import("../Interpreter.zig");
const Log = log_types.Log;
const PlainHost = host.PlainHost;
const Memory = @import("../memory.zig").Memory;

/// Set of possible errors for host instructions.
pub const HostInstructionErrors = Interpreter.InstructionErrors || error{UnexpectedError};

/// Runs the balance opcode for the interpreter.
/// 0x31 -> BALANCE
pub fn balanceInstruction(self: *Interpreter) HostInstructionErrors!void {
    const address = self.stack.pop();
    const bal, const is_cold = self.host.balance(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const gas_usage: u64 = blk: {
        if (self.spec.enabled(.BERLIN))
            break :blk gas.warmOrColdCost(is_cold);

        if (self.spec.enabled(.ISTANBUL))
            break :blk 700;

        if (self.spec.enabled(.TANGERINE))
            break :blk 400;

        break :blk 20;
    };

    try self.gas_tracker.updateTracker(gas_usage);

    self.stack.appendAssumeCapacity(bal);
}

/// Runs the blockhash opcode for the interpreter.
/// 0x40 -> BLOCKHASH
pub fn blockHashInstruction(self: *Interpreter) HostInstructionErrors!void {
    const number = self.stack.pop();
    const as_u64 = std.math.cast(u64, number) orelse return error.Overflow;

    const hash = self.host.blockHash(as_u64) orelse return error.UnexpectedError;

    try self.gas_tracker.updateTracker(constants.BLOCKHASH);

    self.stack.appendAssumeCapacity(@bitCast(hash));
}

/// Runs the extcodecopy opcode for the interpreter.
/// 0x3C -> EXTCODECOPY
pub fn extCodeCopyInstruction(self: *Interpreter) (HostInstructionErrors || Memory.Error || error{Overflow})!void {
    const address = self.stack.pop();
    const offset = self.stack.pop();
    const code_offset = self.stack.pop();
    const length = self.stack.pop();

    const code, const is_cold = self.host.code(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const len = std.math.cast(usize, length) orelse return error.Overflow;
    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;
    const code_offset_usize = std.math.cast(usize, code_offset) orelse return error.Overflow;

    const gas_usage = gas.calculateExtCodeCopyCost(self.spec, len, is_cold);
    try self.gas_tracker.updateTracker(gas_usage orelse return error.OutOfGas);

    if (len == 0)
        return;

    const code_offset_len = @min(code_offset_usize, code.getCodeBytes().len);
    try self.resize(offset_usize +| len);

    self.memory.writeData(offset_usize, code_offset_len, len, code.getCodeBytes());
}

/// Runs the extcodehash opcode for the interpreter.
/// 0x3F -> EXTCODEHASH
pub fn extCodeHashInstruction(self: *Interpreter) HostInstructionErrors!void {
    const address = self.stack.pop();
    const code_hash, const is_cold = self.host.codeHash(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const gas_usage: u64 = blk: {
        if (self.spec.enabled(.BERLIN))
            break :blk gas.warmOrColdCost(is_cold);

        if (self.spec.enabled(.ISTANBUL))
            break :blk 700;

        break :blk 400;
    };

    try self.gas_tracker.updateTracker(gas_usage);

    self.stack.appendAssumeCapacity(@bitCast(code_hash));
}

/// Runs the extcodesize opcode for the interpreter.
/// 0x3B -> EXTCODESIZE
pub fn extCodeSizeInstruction(self: *Interpreter) HostInstructionErrors!void {
    const address = self.stack.pop();
    const code, const is_cold = self.host.code(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const gas_usage = gas.calculateCodeSizeCost(self.spec, is_cold);
    try self.gas_tracker.updateTracker(gas_usage);

    self.stack.appendAssumeCapacity(code.getCodeBytes().len);
}

/// Runs the logs opcode for the interpreter.
/// 0xA0..0xA4 -> LOG0..LOG4
pub inline fn logInstruction(self: *Interpreter, size: u8) (HostInstructionErrors || Memory.Error || error{Overflow})!void {
    std.debug.assert(!self.is_static); // Requires non static calls.

    const offset = self.stack.pop();
    const length = self.stack.pop();

    const len = std.math.cast(usize, length) orelse return error.Overflow;
    try self.gas_tracker.updateTracker(gas.calculateLogCost(size, len) orelse return error.GasOverflow);

    const bytes: []u8 = blk: {
        if (len == 0)
            break :blk &[_]u8{};

        const off = std.math.cast(usize, offset) orelse return error.Overflow;
        try self.resize(off +| len);
        break :blk self.memory.getSlice()[off .. off + len];
    };

    var topic = try std.array_list.Managed(?[32]u8).initCapacity(self.allocator, size);
    errdefer topic.deinit();

    for (0..size) |_| {
        try topic.append(@bitCast(self.stack.popUnsafe() orelse return error.StackUnderflow));
    }

    const env = self.host.getEnviroment();
    const log: Log = .{
        .data = bytes,
        .topics = try topic.toOwnedSlice(),
        .logIndex = null,
        .removed = false,
        .address = self.contract.target_address,
        .blockHash = null,
        .blockNumber = @intCast(env.block.number),
        .transactionIndex = null,
        .transactionHash = null,
    };

    self.host.log(log) catch return error.UnexpectedError;
}

/// Runs the selfbalance opcode for the interpreter.
/// 0x47 -> SELFBALANCE
pub fn selfBalanceInstruction(self: *Interpreter) (HostInstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.ISTANBUL))
        return error.InstructionNotEnabled;

    const bal, _ = self.host.balance(self.contract.target_address) orelse return error.UnexpectedError;

    try self.gas_tracker.updateTracker(constants.FAST_STEP);
    self.stack.appendAssumeCapacity(bal);
}

/// Runs the selfbalance opcode for the interpreter.
/// 0xFF -> SELFDESTRUCT
pub fn selfDestructInstruction(self: *Interpreter) HostInstructionErrors!void {
    std.debug.assert(!self.is_static); // requires non static calls.

    const address = self.stack.pop();
    const result = self.host.selfDestruct(self.contract.target_address, @bitCast(@as(u160, @intCast(address)))) catch return error.UnexpectedError;

    if (self.spec.enabled(.LONDON) and !result.data.previously_destroyed)
        self.gas_tracker.refund_amount += 24000;

    const gas_usage = gas.calculateSelfDestructCost(self.spec, result.data);
    try self.gas_tracker.updateTracker(gas_usage);

    self.status = .self_destructed;
}

/// Runs the sload opcode for the interpreter.
/// 0x54 -> SLOAD
pub fn sloadInstruction(self: *Interpreter) HostInstructionErrors!void {
    const index = self.stack.pop();

    const value = self.host.sload(self.contract.target_address, index) catch return error.UnexpectedError;

    const gas_usage = gas.calculateSloadCost(self.spec, value.cold);
    try self.gas_tracker.updateTracker(gas_usage);

    self.stack.appendAssumeCapacity(value.data);
}

/// Runs the sstore opcode for the interpreter.
/// 0x55 -> SSTORE
pub fn sstoreInstruction(self: *Interpreter) HostInstructionErrors!void {
    std.debug.assert(!self.is_static); // Requires non static calls.

    const index = self.stack.pop();
    const value = self.stack.pop();

    const result = self.host.sstore(self.contract.target_address, index, value) catch return error.UnexpectedError;
    const gas_remaining = self.gas_tracker.availableGas();

    const gas_cost = gas.calculateSstoreCost(
        self.spec,
        result.data.original_value,
        result.data.present_value,
        result.data.new_value,
        gas_remaining,
        result.cold,
    );

    try self.gas_tracker.updateTracker(gas_cost orelse return error.OutOfGas);
    self.gas_tracker.refund_amount = gas.calculateSstoreRefund(
        self.spec,
        result.data.original_value,
        result.data.present_value,
        result.data.new_value,
    );
}

/// Runs the tload opcode for the interpreter.
/// 0x5C -> TLOAD
pub fn tloadInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.pop();

    const load = self.host.tload(self.contract.target_address, index);
    try self.gas_tracker.updateTracker(constants.WARM_STORAGE_READ_COST);

    self.stack.appendAssumeCapacity(load orelse 0);
}

/// Runs the tstore opcode for the interpreter.
/// 0x5D -> TSTORE
pub fn tstoreInstruction(self: *Interpreter) (HostInstructionErrors || error{InstructionNotEnabled})!void {
    std.debug.assert(!self.is_static); // requires non static calls.

    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.pop();
    const value = self.stack.pop();

    self.host.tstore(self.contract.target_address, index, value) catch return error.UnexpectedError;
    try self.gas_tracker.updateTracker(constants.WARM_STORAGE_READ_COST);
}
