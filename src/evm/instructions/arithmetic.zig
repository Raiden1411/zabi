const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const Stack = @import("../../utils/stack.zig").Stack;
const Interpreter = @import("../interpreter.zig");

/// Performs add instruction for the interpreter.
/// ADD -> 0x01
pub fn addInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const addition = first +% second;

    try self.stack.pushUnsafe(addition);
    self.program_counter += 1;
}
/// Performs div instruction for the interpreter.
/// DIV -> 0x04
pub fn divInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(second != 0); // division by 0

    const div = @divFloor(first, second);

    try self.stack.pushUnsafe(div);
    self.program_counter += 1;
}
/// Performs exponent instruction for the interpreter.
/// EXP -> 0x0A
pub fn exponentInstruction(self: *Interpreter) !void {
    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const exp_gas = try gas.calculateExponentCost(second, self.spec);
    try self.gas_tracker.updateTracker(exp_gas);

    const exp = std.math.pow(u256, first, second);
    try self.stack.pushUnsafe(exp);
    self.program_counter += 1;
}
/// Performs addition + mod instruction for the interpreter.
/// ADDMOD -> 0x08
pub fn modAdditionInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const third = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(third != 0); // remainder division by 0

    const add = first +% second;
    const mod = @mod(add, third);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}
/// Performs mod instruction for the interpreter.
/// MOD -> 0x06
pub fn modInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(second != 0); // remainder division by 0

    const mod = @mod(first, second);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}
/// Performs mul + mod instruction for the interpreter.
/// MULMOD -> 0x09
pub fn modMultiplicationInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const third = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(third != 0); // remainder division by 0

    const mul = first *% second;
    const mod = @mod(mul, third);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}
/// Performs mul instruction for the interpreter.
/// MUL -> 0x02
pub fn mulInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const mul = first *% second;

    try self.stack.pushUnsafe(mul);
    self.program_counter += 1;
}
/// Performs signed division instruction for the interpreter.
/// SDIV -> 0x05
pub fn signedDivInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // division by 0

    const div: u256 = @bitCast(@divFloor(casted_first, casted_second));

    try self.stack.pushUnsafe(div);
    self.program_counter += 1;
}
/// Performs signextend instruction for the interpreter.
/// SIGNEXTEND -> 0x0B
pub fn signExtendInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const ext = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const x = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (ext < 31) {
        const bit_index: usize = 8 * @as(usize, @intCast(ext)) + 7;
        const mask = std.math.shl(u256, 1, bit_index);
        const value_mask = mask - 1;

        const neg = (x & mask) != 0;
        try self.stack.pushUnsafe(if (neg) x | ~value_mask else x & value_mask);
    } else {
        try self.stack.pushUnsafe(x);
    }

    self.program_counter += 1;
}
/// Performs sub instruction for the interpreter.
/// SMOD -> 0x07
pub fn signedModInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FAST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // remainder division by 0

    const div = @mod(casted_first, casted_second);

    try self.stack.pushUnsafe(@bitCast(div));
    self.program_counter += 1;
}
/// Performs sub instruction for the interpreter.
/// SUB -> 0x03
pub fn subInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const sub = first -% second;

    try self.stack.pushUnsafe(sub);
    self.program_counter += 1;
}

test "Addition" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try addInstruction(&interpreter);

        try testing.expectEqual(3, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(1);

        try addInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Multiplication" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try mulInstruction(&interpreter);

        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(2);

        try mulInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256) - 1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Subtraction" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try subInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try subInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Division" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try divInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try divInstruction(&interpreter);

        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Signed Division" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));

        try signedDivInstruction(&interpreter);

        try testing.expectEqual(-1, @as(i256, @bitCast(interpreter.stack.popUnsafe().?)));
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try divInstruction(&interpreter);

        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Mod" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try modInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try modInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Signed Mod" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));

        try signedModInstruction(&interpreter);

        try testing.expectEqual(1, @as(i256, @bitCast(interpreter.stack.popUnsafe().?)));
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(1);

        try signedModInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Addition and Mod" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);

        try modAdditionInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u256));
        try interpreter.stack.pushUnsafe(2);

        try modAdditionInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Multiplication and Mod" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(1);

        try modMultiplicationInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(4);
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(2);

        try modMultiplicationInstruction(&interpreter);

        try testing.expectEqual(2, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Exponent" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(2);
        try interpreter.stack.pushUnsafe(2);

        try exponentInstruction(&interpreter);

        try testing.expectEqual(4, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(60, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(std.math.maxInt(u16));

        try exponentInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u16), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(120, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
}

test "Sign Extend" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.spec = .LATEST;

    {
        try interpreter.stack.pushUnsafe(0xFF);
        try interpreter.stack.pushUnsafe(0);

        try signExtendInstruction(&interpreter);

        try testing.expectEqual(std.math.maxInt(u256), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(5, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0);

        try signExtendInstruction(&interpreter);

        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(10, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(0x7f);
        try interpreter.stack.pushUnsafe(0xFF);

        try signExtendInstruction(&interpreter);

        try testing.expectEqual(0x7f, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(15, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(3, interpreter.program_counter);
    }
}
