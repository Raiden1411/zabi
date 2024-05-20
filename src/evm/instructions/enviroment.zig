const enviroment = @import("../enviroment.zig");
const gas = @import("../gas_tracker.zig");
const std = @import("std");

const BlobExcessGasAndPrice = enviroment.BlobExcessGasAndPrice;
const Interpreter = @import("../interpreter.zig");

/// Performs the basefee instruction for the interpreter.
/// 0x48 -> BASEFEE
pub fn baseFeeInstruction(self: *Interpreter) !void {
    const env = self.host.getEnviroment();
    const fee = env.block.base_fee;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(fee);
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
}
/// Performs the blobhash instruction for the interpreter.
/// 0x49 -> BLOBHASH
pub fn blobHashInstruction(self: *Interpreter) !void {
    if (!self.spec.enabled(.CANCUN))
        return error.InstructionNotEnabled;

    const index = self.stack.popUnsafe() orelse return error.StackUnderflow;
    try self.gas_tracker.updateTracker(gas.FASTEST_STEP);

    if (index >= self.host.getEnviroment().tx.blob_hashes.len) {
        try self.stack.pushUnsafe(0);
        return;
    }

    const hash = self.host.getEnviroment().tx.blob_hashes[index];

    try self.stack.pushUnsafe(@bitCast(hash));
}
/// Performs the number instruction for the interpreter.
/// 0x43 -> NUMBER
pub fn blockNumberInstruction(self: *Interpreter) !void {
    const number = self.host.getEnviroment().block.number;
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(number);
}
/// Performs the chainid instruction for the interpreter.
/// 0x46 -> CHAINID
pub fn chainIdInstruction(self: *Interpreter) !void {
    if (self.spec.enabled(.ISTANBUL))
        return error.InstructionNotSupported;

    const chainId = self.host.getEnviroment().config.chain_id;
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(chainId);
}
/// Performs the coinbase instruction for the interpreter.
/// 0x41 -> COINBASE
pub fn coinbaseInstruction(self: *Interpreter) !void {
    const coinbase = self.host.getEnviroment().block.coinbase;
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@bitCast(coinbase));
}
/// Performs the prevrandao/difficulty instruction for the interpreter.
/// 0x44 -> PREVRANDAO/DIFFICULTY
pub fn difficultyInstruction(self: *Interpreter) !void {
    const env = self.host.getEnviroment();
    const difficulty = if (self.spec.enabled(.MERGE)) env.block.prevrandao else env.block.difficulty;

    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(difficulty);
}
/// Performs the origin instruction for the interpreter.
/// 0x32 -> ORIGIN
pub fn originInstruction(self: *Interpreter) !void {
    const origin = self.host.getEnviroment().tx.caller;
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(@bitCast(origin));
}
/// Performs the timestamp instruction for the interpreter.
/// 0x42 -> TIMESTAMP
pub fn timestampInstruction(self: *Interpreter) !void {
    const timestamp = self.host.getEnviroment().block.timestamp;
    try self.gas_tracker.updateTracker(gas.QUICK_STEP);
    try self.stack.pushUnsafe(timestamp);
}
