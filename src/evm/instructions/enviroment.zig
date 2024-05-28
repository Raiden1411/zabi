const enviroment = @import("../enviroment.zig");
const gas = @import("../gas_tracker.zig");
const std = @import("std");
const testing = std.testing;

const BlobExcessGasAndPrice = enviroment.BlobExcessGasAndPrice;
const Interpreter = @import("../Interpreter.zig");
const PlainHost = @import("../host.zig").PlainHost;
const Stack = @import("../../utils/stack.zig").Stack;

/// Performs the basefee instruction for the interpreter.
/// 0x48 -> BASEFEE
pub fn baseFeeInstruction(self: *Interpreter) !void {
    const env = self.host.getEnviroment();
    const fee = env.block.base_fee;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(fee);
    self.program_counter += 1;
}
/// Performs the blobbasefee instruction for the interpreter.
/// 0x4A -> BLOBBASEFEE
pub fn blobBaseFeeInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);

    const blob_price = self.host.getEnviroment().block.blob_excess_gas_and_price orelse BlobExcessGasAndPrice{
        .blob_gasprice = 0,
        .blob_excess_gas = 0,
    };

    try self.stack.pushUnsafe(blob_price.blob_gasprice);
    self.program_counter += 1;
}
/// Performs the blobhash instruction for the interpreter.
/// 0x49 -> BLOBHASH
pub fn blobHashInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    defer self.program_counter += 1;

    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    if (index >= self.host.getEnviroment().tx.blob_hashes.len) {
        try self.stack.pushUnsafe(0);
        return;
    }

    const hash = self.host.getEnviroment().tx.blob_hashes[@intCast(index)];

    try self.stack.pushUnsafe(@bitCast(hash));
}
/// Performs the number instruction for the interpreter.
/// 0x43 -> NUMBER
pub fn blockNumberInstruction(self: *Interpreter) !void {
    const number = self.host.getEnviroment().block.number;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(number);

    self.program_counter += 1;
}
/// Performs the chainid instruction for the interpreter.
/// 0x46 -> CHAINID
pub fn chainIdInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.ISTANBUL))
        return error.InstructionNotEnabled;

    const chainId = self.host.getEnviroment().config.chain_id;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(chainId);

    self.program_counter += 1;
}
/// Performs the coinbase instruction for the interpreter.
/// 0x41 -> COINBASE
pub fn coinbaseInstruction(self: *Interpreter) !void {
    const coinbase = self.host.getEnviroment().block.coinbase;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(coinbase)));

    self.program_counter += 1;
}
/// Performs the prevrandao/difficulty instruction for the interpreter.
/// 0x44 -> PREVRANDAO/DIFFICULTY
pub fn difficultyInstruction(self: *Interpreter) !void {
    const env = self.host.getEnviroment();
    const difficulty = if (self.spec.enabled(.MERGE)) env.block.prevrandao orelse 0 else env.block.difficulty;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(difficulty);

    self.program_counter += 1;
}
/// Performs the gaslimit instruction for the interpreter.
/// 0x45 -> GASLIMIT
pub fn gasLimitInstruction(self: *Interpreter) !void {
    const gas_price = self.host.getEnviroment().block.gas_limit;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(gas_price);

    self.program_counter += 1;
}
/// Performs the gasprice instruction for the interpreter.
/// 0x3A -> GASPRICE
pub fn gasPriceInstruction(self: *Interpreter) !void {
    const gas_price = self.host.getEnviroment().effectiveGasPrice();

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(gas_price);

    self.program_counter += 1;
}
/// Performs the origin instruction for the interpreter.
/// 0x32 -> ORIGIN
pub fn originInstruction(self: *Interpreter) !void {
    const origin = self.host.getEnviroment().tx.caller;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@as(u160, @bitCast(origin)));

    self.program_counter += 1;
}
/// Performs the timestamp instruction for the interpreter.
/// 0x42 -> TIMESTAMP
pub fn timestampInstruction(self: *Interpreter) !void {
    const timestamp = self.host.getEnviroment().block.timestamp;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(timestamp);

    self.program_counter += 1;
}

test "BaseFee" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try baseFeeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "BlobBaseFee" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;

        try blobBaseFeeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, blobBaseFeeInstruction(&interpreter));
    }
}

test "BlobHash" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;

        try interpreter.stack.pushUnsafe(0);
        try blobHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        host.env.tx.blob_hashes = &.{[_]u8{1} ** 32};

        try interpreter.stack.pushUnsafe(0);
        try blobHashInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(2, interpreter.program_counter);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, blobHashInstruction(&interpreter));
    }
}

test "Timestamp" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try timestampInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "BlockNumber" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try blockNumberInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "ChainId" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;
        try chainIdInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
        try testing.expectEqual(1, interpreter.program_counter);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, chainIdInstruction(&interpreter));
    }
}

test "Coinbase" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try coinbaseInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "Difficulty" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try difficultyInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "GasPrice" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try gasPriceInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "Origin" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try originInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}

test "GasLimit" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;
    defer interpreter.stack.deinit();

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = try Stack(u256).initWithCapacity(testing.allocator, 1024);
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try gasLimitInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    try testing.expectEqual(1, interpreter.program_counter);
}
