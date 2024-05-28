const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const Contract = @import("../contract.zig").Contract;
const Interpreter = @import("../interpreter.zig");
const Memory = @import("../memory.zig").Memory;
const Stack = @import("../../utils/stack.zig").Stack;

/// Runs the jumpi instruction opcode for the interpreter.
/// 0x57 -> JUMPI
pub fn conditionalJumpInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);

    const target = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const condition = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const as_usize = std.math.cast(usize, target) orelse return error.InvalidJump;

    if (condition != 0) {
        if (!self.contract.isValidJump(as_usize)) {
            self.status = .invalid_jump;
            return;
        }

        self.program_counter += as_usize;
        return;
    }

    self.program_counter += 1;
}
/// Runs the pc instruction opcode for the interpreter.
/// 0x58 -> PC
pub fn programCounterInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.program_counter);
    self.program_counter += 1;
}
/// Runs the jump instruction opcode for the interpreter.
/// 0x56 -> JUMP
pub fn jumpInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.MID_STEP);
    const target = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const as_usize = std.math.cast(usize, target) orelse return error.InvalidJump;

    if (!self.contract.isValidJump(as_usize)) {
        self.status = .invalid_jump;
        return;
    }

    self.program_counter += as_usize;
}
/// Runs the jumpdest instruction opcode for the interpreter.
/// 0x5B -> JUMPDEST
pub fn jumpDestInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.JUMPDEST);
    self.program_counter += 1;
}
/// Runs the invalid instruction opcode for the interpreter.
/// 0xFE -> INVALID
pub fn invalidInstruction(self: *Interpreter) !void {
    self.status = .invalid;
}
/// Runs the stop instruction opcode for the interpreter.
/// 0x00 -> STOP
pub fn stopInstruction(self: *Interpreter) !void {
    self.status = .stopped;
}
/// Runs the return instruction opcode for the interpreter.
/// 0xF3 -> RETURN
pub fn returnInstruction(self: *Interpreter) !void {
    return returnAction(self, .returned);
}
/// Runs the rever instruction opcode for the interpreter.
/// 0xFD -> REVERT
pub fn revertInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    return returnAction(self, .reverted);
}
/// Runs the stop instruction opcode for the interpreter.
/// 0x00 -> STOP
pub fn unknowInstruction(self: *Interpreter) !void {
    self.status = .opcode_not_found;
}

// Internal action for return type instructions.
fn returnAction(self: *Interpreter, status: Interpreter.InterpreterStatus) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const len = std.math.cast(usize, length) orelse return error.Overflow;
    const off = std.math.cast(usize, offset) orelse return error.Overflow;

    if (len != 0) {
        const return_buffer = try self.allocator.alloc(u8, len);

        try self.resize(utils.saturatedAddition(u64, len, off));
        const slice = self.memory.getSlice();
        @memcpy(return_buffer, slice[off .. off + len]);
        self.return_data = return_buffer;
    }
    self.status = status;
}

test "Program counter" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try programCounterInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "Unknown" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try unknowInstruction(&interpreter);

    try testing.expectEqual(.opcode_not_found, interpreter.status);
}

test "Invalid" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try invalidInstruction(&interpreter);

    try testing.expectEqual(.invalid, interpreter.status);
}

test "Stopped" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try stopInstruction(&interpreter);

    try testing.expectEqual(.stopped, interpreter.status);
}

test "Jumpdest" {
    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;

    try jumpDestInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "Jump" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{0} ** 31 ++ [_]u8{0x5b}) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;

    {
        try interpreter.stack.pushUnsafe(31);
        try jumpInstruction(&interpreter);

        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(31, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(30);
        try jumpInstruction(&interpreter);

        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(31, interpreter.program_counter);
        try testing.expectEqual(.invalid_jump, interpreter.status);
    }
}

test "Conditional Jump" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = @constCast(&[_]u8{0} ** 31 ++ [_]u8{0x5b}) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;

    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(31);
        try conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(8, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(31, interpreter.program_counter);
    }
    {
        try interpreter.stack.pushUnsafe(1);
        try interpreter.stack.pushUnsafe(30);
        try conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(16, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(31, interpreter.program_counter);
        try testing.expectEqual(.invalid_jump, interpreter.status);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(31);
        try conditionalJumpInstruction(&interpreter);

        try testing.expectEqual(24, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(32, interpreter.program_counter);
    }
}

test "Reverted" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
        testing.allocator.free(interpreter.return_data);
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &.{};
    interpreter.allocator = testing.allocator;

    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try revertInstruction(&interpreter);

        try testing.expectEqual(undefined, @as(u256, @bitCast(interpreter.return_data[0..32].*)));
        try testing.expectEqual(.reverted, interpreter.status);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;
        try testing.expectError(error.InstructionNotEnabled, revertInstruction(&interpreter));
    }
}

test "Return" {
    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
        testing.allocator.free(interpreter.return_data);
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &.{};
    interpreter.allocator = testing.allocator;

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);
    try returnInstruction(&interpreter);

    try testing.expectEqual(undefined, @as(u256, @bitCast(interpreter.return_data[0..32].*)));
    try testing.expectEqual(.returned, interpreter.status);
    try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
}
