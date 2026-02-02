const constants = @import("zabi-utils").constants;
const enviroment = @import("../enviroment.zig");
const gas = @import("../gas_tracker.zig");
const std = @import("std");

const BlobExcessGasAndPrice = enviroment.BlobExcessGasAndPrice;
const Interpreter = @import("../Interpreter.zig");
const PlainHost = @import("../host.zig").PlainHost;

/// Performs the basefee instruction for the interpreter.
/// 0x48 -> BASEFEE
pub fn baseFeeInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const env = self.host.getEnviroment();
    const fee = env.block.base_fee;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(fee);
}

/// Performs the blobbasefee instruction for the interpreter.
/// 0x4A -> BLOBBASEFEE
pub fn blobBaseFeeInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);

    const blob_price: BlobExcessGasAndPrice = self.host.getEnviroment().block.blob_excess_gas_and_price orelse .{
        .blob_gasprice = 0,
        .blob_excess_gas = 0,
    };

    self.stack.appendAssumeCapacity(blob_price.blob_gasprice);
}

/// Performs the blobhash instruction for the interpreter.
/// 0x49 -> BLOBHASH
pub fn blobHashInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.pop();
    try self.gas_tracker.updateTracker(constants.FASTEST_STEP);

    if (index >= self.host.getEnviroment().tx.blob_hashes.len) {
        self.stack.appendAssumeCapacity(0);
        return;
    }

    const hash = self.host.getEnviroment().tx.blob_hashes[@intCast(index)];

    self.stack.appendAssumeCapacity(@bitCast(hash));
}

/// Performs the number instruction for the interpreter.
/// 0x43 -> NUMBER
pub fn blockNumberInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const number = self.host.getEnviroment().block.number;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(number);
}

/// Performs the chainid instruction for the interpreter.
/// 0x46 -> CHAINID
pub fn chainIdInstruction(self: *Interpreter) (Interpreter.InstructionErrors || error{InstructionNotEnabled})!void {
    if (!self.spec.enabled(.ISTANBUL))
        return error.InstructionNotEnabled;

    const chainId = self.host.getEnviroment().config.chain_id;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(chainId);
}

/// Performs the coinbase instruction for the interpreter.
/// 0x41 -> COINBASE
pub fn coinbaseInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const coinbase = self.host.getEnviroment().block.coinbase;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(@as(u160, @bitCast(coinbase)));
}

/// Performs the prevrandao/difficulty instruction for the interpreter.
/// 0x44 -> PREVRANDAO/DIFFICULTY
pub fn difficultyInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const env = self.host.getEnviroment();
    const difficulty = if (self.spec.enabled(.MERGE)) env.block.prevrandao orelse 0 else env.block.difficulty;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(difficulty);
}

/// Performs the gaslimit instruction for the interpreter.
/// 0x45 -> GASLIMIT
pub fn gasLimitInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const gas_price = self.host.getEnviroment().block.gas_limit;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(gas_price);
}

/// Performs the gasprice instruction for the interpreter.
/// 0x3A -> GASPRICE
pub fn gasPriceInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const gas_price = self.host.getEnviroment().effectiveGasPrice();

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(gas_price);
}

/// Performs the origin instruction for the interpreter.
/// 0x32 -> ORIGIN
pub fn originInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const origin = self.host.getEnviroment().tx.caller;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(@as(u160, @bitCast(origin)));
}

/// Performs the timestamp instruction for the interpreter.
/// 0x42 -> TIMESTAMP
pub fn timestampInstruction(self: *Interpreter) Interpreter.InstructionErrors!void {
    const timestamp = self.host.getEnviroment().block.timestamp;

    try self.gas_tracker.updateTracker(constants.QUICK_STEP);
    self.stack.appendAssumeCapacity(timestamp);
}
