const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const Interpreter = @import("../Interpreter.zig");
const Memory = @import("../memory.zig").Memory;
const Stack = @import("../../utils/stack.zig").Stack;

/// Runs the mcopy opcode for the interpreter.
/// 0x5E -> MCOPY
pub fn mcopyInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const destination = try self.stack.tryPopUnsafe();
    const source = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.OutOfGas);

    if (len == 0)
        return;

    const source_usize = std.math.cast(usize, source) orelse return error.Overflow;
    const destination_usize = std.math.cast(usize, destination) orelse return error.Overflow;

    const new_size = utils.saturatedAddition(u64, @max(destination_usize, source_usize), len);
    try self.resize(new_size);

    self.memory.memoryCopy(destination_usize, source_usize, len);
}
/// Runs the mload opcode for the interpreter.
/// 0x51 -> MLOAD
pub fn mloadInstruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size = utils.saturatedAddition(u64, as_usize, 32);
    try self.resize(new_size);

    try self.stack.pushUnsafe(self.memory.wordToInt(as_usize));
}
/// Runs the msize opcode for the interpreter.
/// 0x59 -> MSIZE
pub fn msizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.memory.getCurrentMemorySize());
}
/// Runs the mstore opcode for the interpreter.
/// 0x52 -> MSTORE
pub fn mstoreInstruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size = utils.saturatedAddition(u64, as_usize, 32);
    try self.resize(new_size);

    try self.memory.writeInt(as_usize, value);
}
/// Runs the mstore8 opcode for the interpreter.
/// 0x53 -> MSTORE8
pub fn mstore8Instruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();
    const value = try self.stack.tryPopUnsafe();

    const as_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);
    const new_size = utils.saturatedAddition(u64, as_usize, 1);
    try self.resize(new_size);

    var buffer: [32]u8 = undefined;
    std.mem.writeInt(u256, &buffer, value, .little);

    try self.memory.writeByte(as_usize, buffer[0]);
}

test "Mstore" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    {
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(0);

        try mstoreInstruction(&interpreter);

        try testing.expectEqual(69, interpreter.memory.wordToInt(0));
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(69);
        try interpreter.stack.pushUnsafe(1);

        try mstoreInstruction(&interpreter);

        try testing.expectEqual(69, interpreter.memory.wordToInt(1));
        try testing.expectEqual(12, interpreter.gas_tracker.used_amount);
    }
}

test "Mstore8" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    {
        try interpreter.stack.pushUnsafe(0xFFFF);
        try interpreter.stack.pushUnsafe(0);

        try mstore8Instruction(&interpreter);

        try testing.expectEqual(0xFF, interpreter.memory.getMemoryByte(0));
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0x1F);
        try interpreter.stack.pushUnsafe(1);

        try mstore8Instruction(&interpreter);

        try testing.expectEqual(0x1F, interpreter.memory.getMemoryByte(1));
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
}

test "Msize" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    {
        try msizeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    }
    {
        try msizeInstruction(&interpreter);
        try mloadInstruction(&interpreter);
        try msizeInstruction(&interpreter);

        try testing.expectEqual(32, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(12, interpreter.gas_tracker.used_amount);
    }
}

test "MCopy" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    try interpreter.stack.pushUnsafe(0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
    try interpreter.stack.pushUnsafe(32);
    try mstoreInstruction(&interpreter);

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);

    try mcopyInstruction(&interpreter);

    try testing.expectEqual(0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, interpreter.memory.wordToInt(0));
    try testing.expectEqual(15, interpreter.gas_tracker.used_amount);

    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, mcopyInstruction(&interpreter));
    }
}
