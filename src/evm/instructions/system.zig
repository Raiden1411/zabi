const gas = @import("../gas_tracker.zig");
const std = @import("std");
const utils = @import("zabi-utils").utils;

const Contract = @import("../contract.zig").Contract;
const Interpreter = @import("../Interpreter.zig");
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Memory = @import("../memory.zig").Memory;

/// Runs the address instructions opcodes for the interpreter.
/// 0x30 -> ADDRESS
pub fn addressInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(self.contract.target_address)));
}
/// Runs the caller instructions opcodes for the interpreter.
/// 0x33 -> CALLER
pub fn callerInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(self.contract.caller)));
}
/// Runs the calldatacopy instructions opcodes for the interpreter.
/// 0x35 -> CALLDATACOPY
pub fn callDataCopyInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    const offset = try self.stack.tryPopUnsafe();
    const data = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;
    const data_offset = std.math.cast(usize, data) orelse return error.Overflow;

    try self.resize(offset_usize + len);

    self.memory.writeData(offset_usize, data_offset, len, self.contract.input);
}
/// Runs the calldataload instructions opcodes for the interpreter.
/// 0x37 -> CALLDATALOAD
pub fn callDataLoadInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{Overflow})!void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const offset = std.math.cast(usize, first) orelse return error.Overflow;

    var buffer: [32]u8 = [_]u8{0} ** 32;
    if (offset < self.contract.input.len) {
        const count: u8 = @min(32, self.contract.input.len - offset);
        std.debug.assert(count <= 32 and offset + count <= self.contract.input.len);

        const slice = self.contract.input[offset .. offset + count];
        @memcpy(buffer[0..count], slice);
    }

    const as_int = std.mem.readInt(u256, &buffer, .big);

    try self.stack.pushUnsafe(as_int);
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x36 -> CALLDATASIZE
pub fn callDataSizeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.input.len);
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x34 -> CALLVALUE
pub fn callValueInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.value);
}
/// Runs the codecopy instructions opcodes for the interpreter.
/// 0x39 -> CODECOPY
pub fn codeCopyInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    const offset = try self.stack.tryPopUnsafe();
    const code = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;
    const code_offset = std.math.cast(usize, code) orelse return error.Overflow;

    try self.resize(offset_usize + len);

    self.memory.writeData(offset_usize, code_offset, len, self.contract.bytecode.getCodeBytes());
}
/// Runs the codesize instructions opcodes for the interpreter.
/// 0x38 -> CODESIZE
pub fn codeSizeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.contract.bytecode.getCodeBytes().len);
}
/// Runs the gas instructions opcodes for the interpreter.
/// 0x3A -> GAS
pub fn gasInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.gas_tracker.availableGas());
}
/// Runs the keccak instructions opcodes for the interpreter.
/// 0x20 -> KECCAK
pub fn keccakInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    const offset = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;
    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;

    const cost = gas.calculateKeccakCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    var buffer: [32]u8 = undefined;

    if (length == 0) {
        buffer = [_]u8{0} ** 32;
        try self.stack.pushUnsafe(@bitCast(buffer));
    } else {
        const slice = self.memory.getSlice();

        std.debug.assert(slice.len > offset_usize + len); // Indexing out of bounds;

        Keccak256.hash(slice[offset_usize .. offset_usize + len], &buffer, .{});
        try self.resize(offset_usize + len);
        try self.stack.pushUnsafe(std.mem.readInt(u256, &buffer, .big));
    }
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3D -> RETURNDATACOPY
pub fn returnDataSizeInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.return_data.len);
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3E -> RETURNDATASIZE
pub fn returnDataCopyInstruction(self: *Interpreter) (Interpreter.InstructionErrors || Memory.Error || error{Overflow})!void {
    const offset = try self.stack.tryPopUnsafe();
    const data = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const return_offset = std.math.cast(usize, data) orelse return error.Overflow;
    const return_end = return_offset +| len;

    if (return_end > self.return_data.len) {
        self.status = .invalid_offset;
        return;
    }

    if (length != 0) {
        const memory_offset = std.math.cast(usize, offset) orelse return error.Overflow;

        try self.resize(memory_offset + len);
        self.memory.write(memory_offset, self.return_data[return_offset..return_end]);
    }
}
