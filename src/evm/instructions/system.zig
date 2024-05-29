const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const Contract = @import("../contract.zig").Contract;
const Interpreter = @import("../Interpreter.zig");
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Memory = @import("../memory.zig").Memory;
const Stack = @import("../../utils/stack.zig").Stack;

/// Runs the address instructions opcodes for the interpreter.
/// 0x30 -> ADDRESS
pub fn addressInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(self.contract.target_address)));
}
/// Runs the caller instructions opcodes for the interpreter.
/// 0x33 -> CALLER
pub fn callerInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(self.contract.caller)));
}
/// Runs the calldatacopy instructions opcodes for the interpreter.
/// 0x35 -> CALLDATACOPY
pub fn callDataCopyInstruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();
    const data = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;
    const data_offset = std.math.cast(usize, data) orelse return error.Overflow;

    try self.resize(offset_usize + len);

    try self.memory.writeData(offset_usize, data_offset, len, self.contract.input);
}
/// Runs the calldataload instructions opcodes for the interpreter.
/// 0x37 -> CALLDATALOAD
pub fn callDataLoadInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    const first = try self.stack.tryPopUnsafe();
    const offset = std.math.cast(usize, first) orelse return error.Overflow;

    var buffer: [32]u8 = [_]u8{0} ** 32;
    if (offset < self.contract.input.len) {
        const count = @min(32, self.contract.input.len - offset);
        std.debug.assert(count <= 32 and offset + count <= self.contract.input.len);

        const slice = self.contract.input[offset .. offset + count];
        @memcpy(buffer[32 - count ..], slice);
    }

    try self.stack.pushUnsafe(@bitCast(buffer));
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x36 -> CALLDATASIZE
pub fn callDataSizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.input.len);
}
/// Runs the calldatasize instructions opcodes for the interpreter.
/// 0x34 -> CALLVALUE
pub fn callValueInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.contract.value);
}
/// Runs the codecopy instructions opcodes for the interpreter.
/// 0x39 -> CODECOPY
pub fn codeCopyInstruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();
    const code = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const offset_usize = std.math.cast(usize, offset) orelse return error.Overflow;
    const code_offset = std.math.cast(usize, code) orelse return error.Overflow;

    try self.resize(offset_usize + len);

    try self.memory.writeData(offset_usize, code_offset, len, self.contract.bytecode.getCodeBytes());
}
/// Runs the codesize instructions opcodes for the interpreter.
/// 0x38 -> CODESIZE
pub fn codeSizeInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.contract.bytecode.getCodeBytes().len);
}
/// Runs the gas instructions opcodes for the interpreter.
/// 0x3A -> GAS
pub fn gasInstruction(self: *Interpreter) !void {
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    try self.stack.pushUnsafe(self.gas_tracker.availableGas());
}
/// Runs the keccak instructions opcodes for the interpreter.
/// 0x20 -> KECCAK
pub fn keccakInstruction(self: *Interpreter) !void {
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
        try self.stack.pushUnsafe(@bitCast(buffer));
    }
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3D -> RETURNDATACOPY
pub fn returnDataSizeInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.BYZANTIUM))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(self.return_data.len);
}
/// Runs the returndatasize instructions opcodes for the interpreter.
/// 0x3E -> RETURNDATASIZE
pub fn returnDataCopyInstruction(self: *Interpreter) !void {
    const offset = try self.stack.tryPopUnsafe();
    const data = try self.stack.tryPopUnsafe();
    const length = try self.stack.tryPopUnsafe();

    const len = std.math.cast(usize, length) orelse return error.Overflow;

    const cost = gas.calculateMemoryCopyLowCost(len);
    try self.gas_tracker.updateTracker(cost orelse return error.GasOverflow);

    const return_offset = std.math.cast(usize, data) orelse return error.Overflow;
    const return_end = utils.saturatedAddition(usize, return_offset, len);

    if (return_end > self.return_data.len) {
        self.status = .invalid_offset;
        return;
    }

    if (length != 0) {
        const memory_offset = std.math.cast(usize, offset) orelse return error.Overflow;

        try self.resize(memory_offset + len);
        try self.memory.write(memory_offset, self.return_data[return_offset..return_end]);
    }
}

test "Address" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try addressInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Caller" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try callerInstruction(&interpreter);

    try testing.expectEqual(@as(u160, @bitCast([_]u8{1} ** 20)), interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Value" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try callValueInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CodeSize" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try codeSizeInstruction(&interpreter);

    try testing.expectEqual(33, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CallDataSize" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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

    try callDataSizeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Gas" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(1000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;

    try gasInstruction(&interpreter);

    try testing.expectEqual(998, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "ReturnDataSize" {
    const contract = try Contract.init(
        testing.allocator,
        &.{},
        .{ .raw = &.{} },
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
    interpreter.return_data = &.{};

    try returnDataSizeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "CallDataLoad" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
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
        try interpreter.stack.pushUnsafe(0);
        try callDataLoadInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(33);
        try callDataLoadInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
}

test "CallDataCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try callDataCopyInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(64);
        try interpreter.stack.pushUnsafe(0);

        try callDataCopyInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.memory.wordToInt(0));
        try testing.expectEqual(15, interpreter.gas_tracker.used_amount);
    }
}

test "CodeCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &data },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    try interpreter.stack.pushUnsafe(32);
    try interpreter.stack.pushUnsafe(0);
    try interpreter.stack.pushUnsafe(0);

    try codeCopyInstruction(&interpreter);

    try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
    try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
}

test "Keccak256" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);

    {
        try interpreter.memory.resize(32);
        try interpreter.memory.writeInt(0, 0xFFFFFFFF00000000000000000000000000000000000000000000000000000000);

        try interpreter.stack.pushUnsafe(4);
        try interpreter.stack.pushUnsafe(0);

        try keccakInstruction(&interpreter);

        try testing.expectEqual(0x29045a592007d0c246ef02c2223570da9522d0cf0f73282c79a1bc8f0bb2c238, @byteSwap(interpreter.stack.popUnsafe().?));
        try testing.expectEqual(36, interpreter.gas_tracker.used_amount);
    }
    {
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try keccakInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(66, interpreter.gas_tracker.used_amount);
    }
}

test "ReturnDataCopy" {
    var data = [_]u8{1} ** 32;
    const contract = try Contract.init(
        testing.allocator,
        &data,
        .{ .raw = &.{} },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract.deinit(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer {
        interpreter.stack.deinit();
        interpreter.memory.deinit();
    }

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.contract = contract;
    interpreter.memory = Memory.initEmpty(testing.allocator, null);
    interpreter.return_data = &data;

    {
        try interpreter.stack.pushUnsafe(32);
        try interpreter.stack.pushUnsafe(0);
        try interpreter.stack.pushUnsafe(0);

        try returnDataCopyInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast(data)), interpreter.memory.wordToInt(0));
        try testing.expectEqual(9, interpreter.gas_tracker.used_amount);
    }
}
