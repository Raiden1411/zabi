const constants = @import("zabi").utils.constants;
const evm = @import("zabi").evm;
const enviroment = evm.enviroment;
const gas = evm.gas;
const std = @import("std");
const testing = std.testing;

const AccountInfo = evm.host.AccountInfo;
const AccessList = @import("zabi").types.transactions.AccessList;
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(3, interpreter.gas_tracker.usedAmount());
    }
    {
        host.env.tx.blob_hashes = &.{[_]u8{1} ** 32};

        try interpreter.stack.pushUnsafe(0);
        try evm.instructions.enviroment.blobHashInstruction(&interpreter);

        try testing.expectEqual(@as(u256, @bitCast([_]u8{1} ** 32)), interpreter.stack.popUnsafe().?);
        try testing.expectEqual(6, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
        try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
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
    try testing.expectEqual(2, interpreter.gas_tracker.usedAmount());
}

test "insufficient balance" {
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
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
    var env: EVMEnviroment = .{};
    env.tx.gas_limit = 21000;
    env.tx.gas_price = 1_000_000_000;
    env.tx.value = 1_000_000_000_000_000_000;
    env.tx.optimism = .{
        .mint = 1_000_000_000_000_000_000,
    };

    const sender_info = AccountInfo{
        .balance = 21000 * 1_000_000_000,
        .nonce = 0,
        .code_hash = constants.EMPTY_HASH,
        .code = null,
    };

    try env.validateAgainstState(sender_info);
}

test "calculateIntrinsicGas returns base transaction cost for empty call data" {
    var env: EVMEnviroment = .{};
    env.tx.data = &.{};
    env.tx.transact_to = .{ .call = [_]u8{1} ** 20 };

    const intrinsic = try env.calculateIntrinsicGas();
    try testing.expectEqual(constants.TRANSACTION, intrinsic);
}

test "calculateIntrinsicGas uses pre and post Istanbul calldata pricing" {
    var env: EVMEnviroment = .{};
    env.tx.data = @constCast(&[_]u8{ 0x00, 0x01 });

    env.config.spec_id = .FRONTIER;
    const frontier_cost = try env.calculateIntrinsicGas();
    try testing.expectEqual(constants.TRANSACTION + constants.TRANSACTION_ZERO_DATA + constants.TRANSACTION_NON_ZERO_DATA_FRONTIER, frontier_cost);

    env.config.spec_id = .ISTANBUL;
    const istanbul_cost = try env.calculateIntrinsicGas();
    try testing.expectEqual(constants.TRANSACTION + constants.TRANSACTION_ZERO_DATA + constants.TRANSACTION_NON_ZERO_DATA_INIT, istanbul_cost);
}

test "calculateIntrinsicGas includes create and access list costs" {
    const access_list = [_]AccessList{
        .{
            .address = [_]u8{0xAA} ** 20,
            .storageKeys = &[_][32]u8{
                [_]u8{0x01} ** 32,
                [_]u8{0x02} ** 32,
            },
        },
    };

    var env: EVMEnviroment = .{};
    env.config.spec_id = .BERLIN;
    env.tx.transact_to = .create;
    env.tx.access_list = &access_list;

    const intrinsic = try env.calculateIntrinsicGas();
    const expected = constants.TRANSACTION +
        constants.CREATE +
        constants.ACCESS_LIST_ADDRESS +
        (2 * constants.ACCESS_LIST_STORAGE_KEY);
    try testing.expectEqual(expected, intrinsic);
}

test "validateIntrinsicGas rejects transactions below intrinsic gas" {
    var env: EVMEnviroment = .{};
    env.tx.gas_limit = constants.TRANSACTION - 1;

    try testing.expectError(error.IntrinsicGasTooLow, env.validateIntrinsicGas());
}

test "validateTransaction accepts a valid Cancun blob envelope" {
    var valid_hash = [_]u8{0} ** 32;
    valid_hash[0] = constants.VERSIONED_HASH_VERSION_KZG;

    var env: EVMEnviroment = .{};
    env.config.spec_id = .CANCUN;
    env.tx.tx_type = .cancun;
    env.tx.gas_price = 10;
    env.tx.gas_priority_fee = 1;
    env.block.base_fee = 1;
    env.tx.max_fee_per_blob_gas = 5;
    env.tx.blob_hashes = &[_][32]u8{valid_hash};
    env.block.blob_excess_gas_and_price = .{ .blob_gasprice = 4, .blob_excess_gas = 0 };

    try env.validateTransaction();
}

test "validateTransaction rejects invalid Cancun blob envelopes" {
    var valid_hash = [_]u8{0} ** 32;
    valid_hash[0] = constants.VERSIONED_HASH_VERSION_KZG;

    {
        var env: EVMEnviroment = .{};
        env.config.spec_id = .CANCUN;
        env.tx.tx_type = .cancun;
        env.tx.max_fee_per_blob_gas = 1;
        env.tx.blob_hashes = &.{};
        env.block.blob_excess_gas_and_price = .{ .blob_gasprice = 1, .blob_excess_gas = 0 };

        try testing.expectError(error.EmptyBlobs, env.validateTransaction());
    }

    {
        var invalid_hash = [_]u8{0} ** 32;
        invalid_hash[0] = constants.VERSIONED_HASH_VERSION_KZG + 1;

        var env: EVMEnviroment = .{};
        env.config.spec_id = .CANCUN;
        env.tx.tx_type = .cancun;
        env.tx.max_fee_per_blob_gas = 1;
        env.tx.blob_hashes = &[_][32]u8{invalid_hash};
        env.block.blob_excess_gas_and_price = .{ .blob_gasprice = 1, .blob_excess_gas = 0 };

        try testing.expectError(error.BlobVersionNotSupported, env.validateTransaction());
    }

    {
        var blob_hashes = [_][32]u8{[_]u8{0} ** 32} ** (constants.MAX_BLOB_NUMBER_PER_BLOCK + 1);
        for (&blob_hashes) |*hash|
            hash[0] = constants.VERSIONED_HASH_VERSION_KZG;

        var env: EVMEnviroment = .{};
        env.config.spec_id = .CANCUN;
        env.tx.tx_type = .cancun;
        env.tx.max_fee_per_blob_gas = 10;
        env.tx.blob_hashes = &blob_hashes;
        env.block.blob_excess_gas_and_price = .{ .blob_gasprice = 1, .blob_excess_gas = 0 };

        try testing.expectError(error.TooManyBlobs, env.validateTransaction());
    }

    {
        var env: EVMEnviroment = .{};
        env.config.spec_id = .CANCUN;
        env.tx.tx_type = .cancun;
        env.tx.max_fee_per_blob_gas = 1;
        env.tx.blob_hashes = &[_][32]u8{valid_hash};
        env.block.blob_excess_gas_and_price = .{ .blob_gasprice = 2, .blob_excess_gas = 0 };

        try testing.expectError(error.BlobGasPriceHigherThanMax, env.validateTransaction());
    }
}
