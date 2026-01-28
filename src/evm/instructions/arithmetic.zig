const constants = @import("zabi-utils").constants;
const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Interpreter = @import("../Interpreter.zig");

/// Performs add instruction for the interpreter.
/// ADD -> 0x01
pub fn addInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    second.* = first +% second.*;
}

/// Performs div instruction for the interpreter.
/// DIV -> 0x04
pub fn divInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    if (second.* == 0) {
        @branchHint(.cold);

        return;
    }

    if (fitsInU128(first) and fitsInU128(second.*)) {
        @branchHint(.likely);
        second.* = @as(u128, @truncate(first)) / @as(u128, @truncate(second.*));

        return;
    }

    second.* = first / second.*;
}

/// Performs exponent instruction for the interpreter.
/// EXP -> 0x0A
pub fn exponentInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{Overflow})!void {
    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const exp_gas = try gas.calculateExponentCost(second.*, self.spec);
    try self.gas_tracker.updateTracker(exp_gas);

    const exp = std.math.pow(u256, first, second.*);

    second.* = exp;
}

/// Performs addition + mod instruction for the interpreter.
/// ADDMOD -> 0x08
pub fn modAdditionInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.MID_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();
    const third = try self.stack.tryPeek();

    const add = first +% second;

    third.* = if (third.* == 0) add else @mod(add, third.*);
}

/// Performs mod instruction for the interpreter.
/// MOD -> 0x06
pub fn modInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    if (second.* == 0) {
        @branchHint(.cold);

        return;
    }

    if (fitsInU128(first) and fitsInU128(second.*)) {
        @branchHint(.likely);
        second.* = @as(u128, @truncate(first)) % @as(u128, @truncate(second.*));

        return;
    }

    second.* = @mod(first, second.*);
}

/// Performs mul + mod instruction for the interpreter.
/// MULMOD -> 0x09
pub fn modMultiplicationInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.MID_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPopUnsafe();
    const third = try self.stack.tryPeek();

    const mul = first *% second;

    if (third.* == 0) {
        @branchHint(.cold);
        third.* = mul;

        return;
    }

    third.* = @mod(mul, third.*);
}

/// Performs mul instruction for the interpreter.
/// MUL -> 0x02
pub fn mulInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const mul = first *% second.*;

    second.* = mul;
}

/// Performs signed division instruction for the interpreter.
/// SDIV -> 0x05
pub fn signedDivInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    if (second.* == 0) {
        @branchHint(.unlikely);
        second.* = 0;

        return;
    }

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second.*);

    const sign: u256 = @bitCast((casted_first ^ casted_second) >> 255);

    const abs_n = (casted_first ^ (casted_first >> 255)) -% (casted_first >> 255);
    const abs_d = (casted_second ^ (casted_second >> 255)) -% (casted_second >> 255);

    const abs_n_u: u256 = @bitCast(abs_n);
    const abs_d_u: u256 = @bitCast(abs_d);

    const res = blk: {
        if (fitsInU128(abs_n_u) and fitsInU128(abs_d_u)) {
            @branchHint(.likely);
            break :blk @as(u128, @truncate(abs_n_u)) / @as(u128, @truncate(abs_d_u));
        } else break :blk abs_n_u / abs_d_u;
    };

    second.* = (res ^ sign) -% sign;
}

/// Performs signextend instruction for the interpreter.
/// SIGNEXTEND -> 0x0B
pub fn signExtendInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const ext = try self.stack.tryPopUnsafe();
    const x = try self.stack.tryPopUnsafe();

    if (ext < 31) {
        const bit_index: usize = 8 * @as(usize, @intCast(ext)) + 7;
        const mask = std.math.shl(u256, 1, bit_index);
        const value_mask = mask - 1;

        const neg = (x & mask) != 0;
        try self.stack.pushUnsafe(if (neg) x | ~value_mask else x & value_mask);
    } else {
        try self.stack.pushUnsafe(x);
    }
}

/// Performs sub instruction for the interpreter.
/// SMOD -> 0x07
pub fn signedModInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FAST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    if (second.* == 0) {
        @branchHint(.cold);

        return;
    }

    const casted_first: i256 = @bitCast(first);
    const casted_second: i256 = @bitCast(second.*);

    const abs_n = (casted_first ^ (casted_first >> 255)) -% (casted_first >> 255);
    const abs_d = (casted_second ^ (casted_second >> 255)) -% (casted_second >> 255);

    const abs_n_u: u256 = @bitCast(abs_n);
    const abs_d_u: u256 = @bitCast(abs_d);

    const abs_res = blk: {
        if (fitsInU128(abs_n_u) and fitsInU128(abs_d_u)) {
            @branchHint(.likely);
            break :blk @as(u128, @truncate(abs_n_u)) % @as(u128, @truncate(abs_d_u));
        } else break :blk abs_n_u / abs_d_u;
    };

    // Apply sign of dividend
    const sign: u256 = @bitCast(casted_first >> 255);
    second.* = (abs_res ^ sign) -% sign;
}

/// Performs sub instruction for the interpreter.
/// SUB -> 0x03
pub fn subInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const second = try self.stack.tryPeek();

    const sub = first -% second.*;

    second.* = sub;
}

/// Check if a u256 fits in u128 by examining the high bits.
inline fn fitsInU128(value: u256) bool {
    return @as(u128, @truncate(value >> 128)) == 0;
}
