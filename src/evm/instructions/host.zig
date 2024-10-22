const gas = @import("../gas_tracker.zig");
const host = @import("../host.zig");
const log_types = @import("../../types/log.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const Interpreter = @import("../Interpreter.zig");
const Log = log_types.Log;
const PlainHost = host.PlainHost;
const Memory = @import("../memory.zig").Memory;
const Stack = @import("../../utils/stack.zig").Stack;

/// Set of possible errors for host instructions.
pub const HostInstructionErrors = Interpreter.InstructionErrors || error{UnexpectedError};

/// Runs the balance opcode for the interpreter.
/// 0x31 -> BALANCE
pub fn balanceInstruction(self: *Interpreter) HostInstructionErrors!void {
    const address = try self.stack.tryPopUnsafe();
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

    try self.stack.pushUnsafe(bal);
}
/// Runs the blockhash opcode for the interpreter.
/// 0x40 -> BLOCKHASH
pub fn blockHashInstruction(self: *Interpreter) HostInstructionErrors!void {
    const number = try self.stack.tryPopUnsafe();

    const hash = self.host.blockHash(number) orelse return error.UnexpectedError;

    try self.gas_tracker.updateTracker(gas.BLOCKHASH);

    try self.stack.pushUnsafe(@bitCast(hash));
}
/// Runs the extcodecopy opcode for the interpreter.
/// 0x3B -> EXTCODECOPY
pub fn extCodeCopyInstruction(self: *Interpreter) (HostInstructionErrors || Memory.Error || error{Overflow})!void {
    const address = try self.stack.tryPopUnsafe();
    const offset = try self.stack.tryPopUnsafe();
    const code_offset = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

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
    const address = try self.stack.tryPopUnsafe();
    const code_hash, const is_cold = self.host.codeHash(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const gas_usage: u64 = blk: {
        if (self.spec.enabled(.BERLIN))
            break :blk gas.warmOrColdCost(is_cold);

        if (self.spec.enabled(.ISTANBUL))
            break :blk 700;

        break :blk 400;
    };

    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(@bitCast(code_hash));
}
/// Runs the extcodesize opcode for the interpreter.
/// 0x3B -> EXTCODESIZE
pub fn extCodeSizeInstruction(self: *Interpreter) HostInstructionErrors!void {
    const address = try self.stack.tryPopUnsafe();
    const code, const is_cold = self.host.code(@bitCast(@as(u160, @intCast(address)))) orelse return error.UnexpectedError;

    const gas_usage = gas.calculateCodeSizeCost(self.spec, is_cold);
    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(code.getCodeBytes().len);
}
/// Runs the logs opcode for the interpreter.
/// 0xA0..0xA4 -> LOG0..LOG4
pub fn logInstruction(self: *Interpreter, size: u8) (HostInstructionErrors || Memory.Error || error{Overflow})!void {
    std.debug.assert(!self.is_static); // Requires non static calls.

    const offset = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(u64, length) orelse return error.Overflow;
    try self.gas_tracker.updateTracker(gas.calculateLogCost(size, len) orelse return error.GasOverflow);

    const bytes: []u8 = blk: {
        if (len == 0)
            break :blk &[_]u8{};

        const off = std.math.cast(u64, offset) orelse return error.Overflow;
        try self.resize(off +| len);
        break :blk self.memory.getSlice()[off .. off + len];
    };

    var topic = try std.ArrayList(?[32]u8).initCapacity(self.allocator, size);
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
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    try self.stack.pushUnsafe(bal);
}
/// Runs the selfbalance opcode for the interpreter.
/// 0xFF -> SELFDESTRUCT
pub fn selfDestructInstruction(self: *Interpreter) HostInstructionErrors!void {
    std.debug.assert(!self.is_static); // requires non static calls.

    const address = try self.stack.tryPopUnsafe();
    const result = self.host.selfDestruct(self.contract.target_address, @bitCast(@as(u160, @intCast(address)))) catch return error.UnexpectedError;

    if (self.spec.enabled(.LONDON) and !result.previously_destroyed)
        self.gas_tracker.refund_amount += 24000;

    const gas_usage = gas.calculateSelfDestructCost(self.spec, result);
    try self.gas_tracker.updateTracker(gas_usage);

    self.status = .self_destructed;
}
/// Runs the sload opcode for the interpreter.
/// 0x54 -> SLOAD
pub fn sloadInstruction(self: *Interpreter) HostInstructionErrors!void {
    const index = try self.stack.tryPopUnsafe();

    const value, const is_cold = self.host.sload(self.contract.target_address, index) catch return error.UnexpectedError;

    const gas_usage = gas.calculateSloadCost(self.spec, is_cold);
    try self.gas_tracker.updateTracker(gas_usage);

    try self.stack.pushUnsafe(value);
}
/// Runs the sstore opcode for the interpreter.
/// 0x55 -> SSTORE
pub fn sstoreInstruction(self: *Interpreter) HostInstructionErrors!void {
    std.debug.assert(!self.is_static); // Requires non static calls.

    const index = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    const result = self.host.sstore(self.contract.target_address, index, value) catch return error.UnexpectedError;
    const gas_remaining = self.gas_tracker.availableGas();

    const gas_cost = gas.calculateSstoreCost(self.spec, result.original_value, result.present_value, result.new_value, gas_remaining, result.is_cold);

    try self.gas_tracker.updateTracker(gas_cost orelse return error.OutOfGas);
    self.gas_tracker.refund_amount = gas.calculateSstoreRefund(self.spec, result.original_value, result.present_value, result.new_value);
}
/// Runs the tload opcode for the interpreter.
/// 0x5C -> TLOAD
pub fn tloadInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = try self.stack.tryPopUnsafe();

    const load = self.host.tload(self.contract.target_address, index);
    try self.gas_tracker.updateTracker(gas.WARM_STORAGE_READ_COST);

    try self.stack.pushUnsafe(load orelse 0);
}
/// Runs the tstore opcode for the interpreter.
/// 0x5D -> TSTORE
pub fn tstoreInstruction(self: *Interpreter) (HostInstructionErrors || error{InstructionNotEnabled})!void {
    std.debug.assert(!self.is_static); // requires non static calls.

    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    self.host.tstore(self.contract.target_address, index, value) catch return error.UnexpectedError;
    try self.gas_tracker.updateTracker(gas.WARM_STORAGE_READ_COST);
}

test "Balance" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1200, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(@as(u160, @bitCast([_]u8{1} ** 20)));
        try balanceInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1220, interpreter.gas_tracker.used_amount);
    }
}

test "BlockHash" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    try interpreter.stack.pushUnsafe(0);
    try blockHashInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(20, interpreter.gas_tracker.used_amount);
}

test "ExtCodeCopy" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);

    try extCodeCopyInstruction(&interpreter);

    try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
}

test "ExtCodeHash" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try extCodeHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(1200, interpreter.gas_tracker.used_amount);
    }
}

test "ExtCodeSize" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(800, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try extCodeSizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(820, interpreter.gas_tracker.used_amount);
    }
}

test "Log" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.host = plain.host();
    interpreter.allocator = testing.allocator;

    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try logInstruction(&interpreter, 0);

        try testing.expectEqual(375, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try logInstruction(&interpreter, 1);

        try testing.expectEqual(1384, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);
        try logInstruction(&interpreter, 2);

        try testing.expectEqual(2509, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try logInstruction(&interpreter, 3);

        try testing.expectEqual(4017, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(3);
        try logInstruction(&interpreter, 4);

        try testing.expectEqual(5908, interpreter.gas_tracker.used_amount);
    }
}

test "SelfBalance" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    interpreter.spec = .LATEST;
    try selfBalanceInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(5, interpreter.gas_tracker.used_amount);

    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, selfBalanceInstruction(&interpreter));
    }
}

test "Sload" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2600, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3400, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3600, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try sloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3650, interpreter.gas_tracker.used_amount);
    }
}

test "Sstore" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try sstoreInstruction(&interpreter);

        try testing.expectEqual(2200, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .ISTANBUL;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try sstoreInstruction(&interpreter);

        try testing.expectEqual(2300, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .TANGERINE;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try sstoreInstruction(&interpreter);

        try testing.expectEqual(7300, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try sstoreInstruction(&interpreter);

        try testing.expectEqual(12300, interpreter.gas_tracker.used_amount);
    }
}

test "Tload" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try tloadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, tloadInstruction(&interpreter));
    }
}

test "Tstore" {
    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = plain.host();

    {
        interpreter.spec = .LATEST;
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(32);
        try tstoreInstruction(&interpreter);

        try testing.expectEqual(100, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .HOMESTEAD;
        try testing.expectError(error.InstructionNotEnabled, tstoreInstruction(&interpreter));
    }
}
