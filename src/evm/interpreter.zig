const gas = @import("gas_tracker.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const GasTracker = gas.GasTracker;
const Opcodes = @import("opcodes.zig").Opcodes;
const Stack = @import("../utils/stack.zig").Stack;

const Interpreter = @This();

pub const InterpreterStatus = enum {
    Ended,
    Running,
    Returned,
    Reverted,
    Stopped,
};

/// Interpreter allocator used to manage memory.
allocator: Allocator,
/// compiled bytecode that will get ran.
code: []u8,
/// Tracker for used gas by the interpreter.
gas_tracker: GasTracker,
/// the interpreter's counter.
program_counter: u64,
/// The stack of the interpreter with 1024 max size.
stack: *Stack(u256),
/// The current interpreter status.
status: InterpreterStatus,

/// Sets the interpreter to it's expected initial state.
/// `code` is expected to be a hex string of compiled bytecode.
pub fn init(self: *Interpreter, allocator: Allocator, code: []const u8, gas_limit: u64) !void {
    const stack = try allocator.create(Stack(u256));
    errdefer allocator.destroy(stack);

    stack.* = try Stack(u256).initWithCapacity(allocator, 1024);

    const bytecode = if (std.mem.startsWith(u8, code, "0x")) code[2..] else code;
    const buffer = try allocator.alloc(u8, @divExact(bytecode.len, 2));
    errdefer allocator.free(buffer);

    _ = try std.fmt.hexToBytes(buffer, bytecode);

    self.* = .{
        .allocator = allocator,
        .code = buffer,
        .gas_tracker = GasTracker.init(gas_limit),
        .program_counter = 0,
        .stack = stack,
        .status = .Running,
    };
}
/// Clear memory and destroy's any created pointers.
pub fn deinit(self: *Interpreter) void {
    self.stack.deinit();

    self.allocator.free(self.code);
    self.allocator.destroy(self.stack);

    self.* = undefined;
}
/// Run a instruction based on the defined opcodes.
pub fn runInstruction(self: *Interpreter) !void {
    if (self.program_counter > self.code.len - 1) {
        self.status = .Ended;
        return;
    }

    const instruction = self.code[self.program_counter];

    const opcode = try Opcodes.toOpcode(instruction);

    switch (opcode) {
        .STOP => self.stopInstruction(),
        .ADD => try self.addInstruction(),
        .MUL => try self.mulInstruction(),
        .SUB => try self.subInstruction(),
        .DIV => try self.divInstruction(),
        .SDIV => try self.signedDivInstruction(),
        .MOD => try self.modInstruction(),
        .SMOD => try self.signedModInstruction(),
        .ADDMOD => try self.modAdditionInstruction(),
        .MULMOD => try self.modMultiplicationInstruction(),
        .EXP => try self.exponentInstruction(),
        .SIGNEXTEND => try self.signedExponentInstruction(),
        .LT => try self.lowerThanInstruction(),
        else => return error.UnsupportedOpcode,
    }
}

// Opcode instructions
fn stopInstruction(self: *Interpreter) void {
    self.status = .Stopped;
}

fn addInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const addition = first +% second;

    try self.stack.pushUnsafe(addition);
    self.program_counter += 1;
}

fn divInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(second != 0); // division by 0

    const div = @divFloor(first, second);

    try self.stack.pushUnsafe(div);
    self.program_counter += 1;
}

fn exponentInstruction(self: *Interpreter) error{StackUnderflow}!void {
    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const exp_gas = gas.exponentGasCost(second);
    try self.gas_tracker.updateTracker(exp_gas);

    const exp = std.math.pow(u256, first, second);
    try self.stack.pushUnsafe(exp);
    self.program_counter += 1;
}

fn lowerThanInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    try self.stack.pushUnsafe(@intFromBool(first < second));
    self.program_counter += 1;
}

fn modAdditionInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasMidStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const third = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(third != 0); // remainder division by 0

    const add = first +% second;
    const mod = @mod(add, third);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}

fn modInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(second != 0); // remainder division by 0

    const mod = @mod(first, second);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}

fn modMultiplicationInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasMidStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const third = self.stack.popUnsafe() orelse return error.StackUnderflow;

    std.debug.assert(third != 0); // remainder division by 0

    const mul = first *% second;
    const mod = @mod(mul, third);

    try self.stack.pushUnsafe(mod);
    self.program_counter += 1;
}

fn mulInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const mul = first *% second;

    try self.stack.pushUnsafe(mul);
    self.program_counter += 1;
}

fn signedDivInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // division by 0

    const div = @divFloor(casted_first, casted_second);

    try self.stack.pushUnsafe(div);
    self.program_counter += 1;
}

fn signedExponentInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const exp = std.math.pow(i256, first, second);

    try self.stack.pushUnsafe(exp);
    self.program_counter += 1;
}

fn signedModInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second);

    std.debug.assert(casted_second != 0); // remainder division by 0

    const div = @mod(casted_first, casted_second);

    try self.stack.pushUnsafe(div);
    self.program_counter += 1;
}

fn subInstruction(self: *Interpreter) error{StackUnderflow}!void {
    try self.gas_tracker.updateTracker(gas.GasFastestStep);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const second = self.stack.popUnsafe() orelse return error.StackUnderflow;

    const sub = first -% second;

    try self.stack.pushUnsafe(sub);
    self.program_counter += 1;
}
