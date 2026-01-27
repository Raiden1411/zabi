const constants = @import("zabi").utils.constants;
const evm = @import("zabi").evm;
const enviroment = evm.enviroment;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const AccountInfo = evm.host.AccountInfo;
const BlobExcessGasAndPrice = enviroment.BlobExcessGasAndPrice;
const EVMEnviroment = enviroment.EVMEnviroment;
const Interpreter = evm.Interpreter;
const PlainHost = evm.host.PlainHost;

test "BaseFee" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.baseFeeInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "BlobBaseFee" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;

        try evm.instructions.enviroment.blobBaseFeeInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, evm.instructions.enviroment.blobBaseFeeInstruction(&interpreter));
    }
}

test "BlobHash" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;

        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.enviroment.blobHashInstruction(&interpreter);

        try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(3, interpreter.gas_tracker.used_amount);
    }
    {
        host.env.tx.blob_hashes = &.{[_]u8{1} ** 32};

        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.enviroment.blobHashInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, evm.instructions.enviroment.blobHashInstruction(&interpreter));
    }
}

test "Timestamp" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.timestampInstruction(&interpreter);

    try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "BlockNumber" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.blockNumberInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "ChainId" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    {
        interpreter.spec = .LATEST;
        try evm.instructions.enviroment.chainIdInstruction(&interpreter);

        try testing.expectEqual(1, interpreter.stack.popUnsafe().?);
        try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
    }
    {
        interpreter.spec = .FRONTIER;

        try testing.expectError(error.InstructionNotEnabled, evm.instructions.enviroment.chainIdInstruction(&interpreter));
    }
}

test "Coinbase" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.coinbaseInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Difficulty" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.difficultyInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "GasPrice" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.gasPriceInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "Origin" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.originInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "GasLimit" {
    var host: PlainHost = undefined;
    defer host.deinit();

    host.init(testing.allocator);

    var interpreter: Interpreter = undefined;

    interpreter.gas_tracker = gas.GasTracker.init(30_000_000);
    interpreter.stack = .{ .len = 0 };
    interpreter.program_counter = 0;
    interpreter.host = host.host();

    try evm.instructions.enviroment.gasLimitInstruction(&interpreter);

    try testing.expectEqual(0, interpreter.stack.popUnsafe().?);
    try testing.expectEqual(2, interpreter.gas_tracker.used_amount);
}

test "insufficient balance" {
    var env = EVMEnviroment.default();
    env.tx.gas_limit = 21000;
    env.tx.gas_price = 1_000_000_000;
    env.tx.value = 1_000_000_000_000_000_000;

    const sender_info = AccountInfo{
        .balance = 100,
        .nonce = 0,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try testing.expectError(error.InsufficientBalance, env.validateAgainstState(sender_info));
}

test "sufficient balance passes" {
    var env = EVMEnviroment.default();
    env.tx.gas_limit = 21000;
    env.tx.gas_price = 1_000_000_000;
    env.tx.value = 0;

    const sender_info = AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 0,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}

test "invalid nonce" {
    var env = EVMEnviroment.default();
    env.tx.nonce = 5;

    const sender_info = AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 3,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try testing.expectError(error.InvalidNonce, env.validateAgainstState(sender_info));
}

test "nonce null bypasses check" {
    var env = EVMEnviroment.default();
    env.tx.nonce = null;

    const sender_info = AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 999,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}

test "sender has code (EIP-3607)" {
    var env = EVMEnviroment.default();
    env.tx.nonce = 0;

    const sender_info = AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 0,
        .code_hash = [_]u8{0xab} ** 32,
        .code = null,
    };

    try testing.expectError(error.SenderHasCode, env.validateAgainstState(sender_info));
}

test "disable_eip3607 bypasses code check" {
    var env = EVMEnviroment.default();
    env.config.disable_eip3607 = true;
    env.tx.nonce = 0;

    const sender_info = AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 0,
        .code_hash = [_]u8{0xab} ** 32,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}

test "disable_balance_check bypasses balance" {
    var env = EVMEnviroment.default();
    env.config.disable_balance_check = true;
    env.tx.gas_limit = 21000;
    env.tx.gas_price = 1_000_000_000;
    env.tx.value = 1_000_000_000_000_000_000;

    const sender_info = AccountInfo{
        .balance = 0,
        .nonce = 0,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}

test "optimism mint reduces required balance" {
    var env = EVMEnviroment.default();
    env.tx.gas_limit = 21000;
    env.tx.gas_price = 1_000_000_000;
    env.tx.value = 1_000_000_000_000_000_000;
    env.tx.optimism.mint = 1_000_000_000_000_000_000;

    const sender_info = AccountInfo{
        .balance = 21000 * 1_000_000_000,
        .nonce = 0,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}
