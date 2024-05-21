const gas = @import("../gas_tracker.zig");
const std = @import("std");

const Interpreter = @import("../interpreter.zig");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Runs the address instructions opcodes for the interpreter.
/// 0x30 -> ADDRESS
pub fn addressInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@bitCast(self.contract.target_address));
    self.program_counter += 1;
}
/// Runs the caller instructions opcodes for the interpreter.
/// 0x33 -> CALLER
pub fn callerInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@bitCast(self.contract.caller));
    self.program_counter += 1;
}
/// Runs the calldatacopy instructions opcodes for the interpreter.
/// 0x35 -> CALLDATACOPY
pub fn callDataCopyInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const data = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < length)
        return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(length);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    if (comptime std.math.maxInt(u64) < offset)
        return error.Overflow;

    const data_offset: u64 = @truncate(data);
    try self.resize(offset + length);

    try self.memory.writeData(offset, data_offset, length, self.contract.input);
    self.program_counter += 1;
}
/// Runs the calldataload instructions opcodes for the interpreter.
/// 0x37 -> CALLDATALOAD
pub fn callDataLoadInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const offset: u64 = @truncate(first);

    var buffer: [32]u8 = [_]u8{0} ** 32;
    if (offset < self.contract.input.len) {
        const count = @min(32, self.contract.input.len - offset);
        std.debug.assert(count <= 32 and offset + count <= self.contract.input.len);
        const slice = self.contract.input[offset .. offset + count];
        @memcpy(buffer[32 - count ..], slice);
    }

    try self.stack.pushUnsafe(@bitCast(buffer));
    self.program_counter += 1;
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x36 -> CALLDATASIZE
pub fn callDataSizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.input.len);
    self.program_counter += 1;
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x34 -> CALLVALUE
pub fn callValueInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.value);
    self.program_counter += 1;
}
/// Runs the codecopy instructions opcodes for the interpreter.
/// 0x39 -> CODECOPY
pub fn codeCopyInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const code = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < length)
        return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(length);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    if (comptime std.math.maxInt(u64) < offset)
        return error.Overflow;

    const code_offset: u64 = @truncate(code);
    try self.resize(offset + length);

    try self.memory.writeData(offset, code_offset, length, self.contract.bytecode);
    self.program_counter += 1;
}
/// Runs the codesize instructions opcodes for the interpreter.
/// 0x38 -> CODESIZE
pub fn codeSizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.contract.bytecode.len);
    self.program_counter += 1;
}
/// Runs the gas instructions opcodes for the interpreter.
/// 0x3A -> GAS
pub fn gasInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.gas_tracker.availableGas());
    self.program_counter += 1;
}
/// Runs the keccak instructions opcodes for the interpreter.
/// 0x20 -> KECCAK
pub fn keccakInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < length)
        return error.Overflow;

    const cost = gas.calculateKeccakCost(@intCast(length));
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    var buffer: [32]u8 = undefined;

    if (length == 0) {
        buffer = [_]u8{0} ** 32;
        try self.stack.pushUnsafe(@bitCast(buffer));
    } else {
        const slice = self.memory.getSlice();

        std.debug.assert(slice.len > offset + length); // Indexing out of bounds;

        Keccak256.hash(slice[offset .. offset + length], &buffer, .{});
        try self.resize(offset + length);
        try self.stack.pushUnsafe(@bitCast(buffer));
    }

    self.program_counter += 1;
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3D -> RETURNDATACOPY
pub fn returnDataCopyInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.return_data.len);
    self.program_counter += 1;
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3E -> RETURNDATASIZE
pub fn returnDataSizeInstruction(self: *Interpreter) !void {
    const offset = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const data = self.stack.popUnsafe() orelse return error.StackUnderflow;
    const length = self.stack.popUnsafe() orelse return error.StackUnderflow;

    if (comptime std.math.maxInt(u64) < length)
        return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(length);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const return_offset: u64 = @truncate(data);
    const return_end: u64 = @truncate(return_offset + length);

    if (return_end > self.return_data.len) {
        self.status = .InvalidOffset;
        return;
    }

    if (length != 0) {
        const memory_offset: u64 = @truncate(offset);

        try self.resize(memory_offset + length);
        try self.memory.write(memory_offset, self.return_data[return_offset..return_end]);
    }

    self.program_counter += 1;
}
