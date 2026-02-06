const constants = @import("zabi").utils.constants;
const evm_mod = @import("zabi").evm;
const std = @import("std");
const testing = std.testing;

const Account = evm_mod.host.Account;
const AccountInfo = evm_mod.host.AccountInfo;
const Bytecode = evm_mod.bytecode.Bytecode;
const Contract = evm_mod.contract.Contract;
const EVMEnviroment = evm_mod.enviroment.EVMEnviroment;
const EVM = evm_mod.EVM;
const JournaledHost = evm_mod.host.JournaledHost;
const JournaledState = evm_mod.journal.JournaledState;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const MemoryDatabase = evm_mod.database.MemoryDatabase;
const PlainDatabase = evm_mod.database.PlainDatabase;
const StorageSlot = evm_mod.host.StorageSlot;

var mem_db: MemoryDatabase = undefined;
var journal_state: JournaledState = undefined;

const TestAddresses = struct {
    const caller: [20]u8 = [_]u8{0xCA} ** 20;
    const target: [20]u8 = [_]u8{0xDE} ** 20;
};

const TestBytecode = struct {
    const push_add_stop = &[_]u8{ 0x60, 0x01, 0x60, 0x02, 0x01, 0x00 };

    const store_and_return = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0x00
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 0x20
        0x60, 0x00, // PUSH1 0x00
        0xf3, // RETURN
    };

    const sstore_sload_return = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0x00
        0x55, // SSTORE (store 0x42 at slot 0)
        0x60, 0x00, // PUSH1 0x00
        0x54, // SLOAD (load from slot 0)
        0x60, 0x00, // PUSH1 0x00
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 0x20
        0x60, 0x00, // PUSH1 0x00
        0xf3, // RETURN
    };

    const revert_empty = &[_]u8{ 0x60, 0x00, 0x60, 0x00, 0xfd };

    const invalid_opcode = &[_]u8{0xfe};

    const stack_underflow = &[_]u8{0x01};

    const complex_arithmetic = &[_]u8{
        0x60, 0x03, // PUSH1 3
        0x60, 0x05, // PUSH1 5
        0x01, // ADD -> 8
        0x60, 0x02, // PUSH1 2
        0x02, // MUL -> 16
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    const sstore_then_revert = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0x00
        0x55, // SSTORE (store 0x42 at slot 0)
        0x60, 0x00, // PUSH1 0x00
        0x60, 0x00, // PUSH1 0x00
        0xfd, // REVERT
    };
};

const TestFixture = struct {
    host: JournaledHost,
    mem_db: MemoryDatabase,

    fn deinit(self: *TestFixture) void {
        self.host.journal.deinit();
        self.mem_db.deinit();
    }
};

const TestConfig = struct {
    caller: [20]u8 = TestAddresses.caller,
    target: [20]u8 = TestAddresses.target,
    gas_limit: u64 = 100_000,
    value: u256 = 0,
    nonce: ?u64 = 0,
    caller_balance: u256 = 1_000_000,
    caller_nonce: u64 = 0,
    target_code: []const u8 = TestBytecode.push_add_stop,
    disable_balance_check: bool = false,
    disable_block_gas_limit: bool = true,
};

fn createTestEnvironment(config: TestConfig) !TestFixture {
    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = config.caller_nonce,
        .code = null,
        .balance = config.caller_balance,
    };
    try mem_db.addAccountInfo(config.caller, &caller_info);

    var code_hash: [32]u8 = undefined;
    Keccak256.hash(config.target_code, &code_hash, .{});

    var target_info: AccountInfo = .{
        .code_hash = code_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(config.target_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(config.target, &target_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    const host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{
                .spec_id = .LATEST,
                .disable_balance_check = config.disable_balance_check,
                .disable_block_gas_limit = config.disable_block_gas_limit,
            },
            .block = .{
                .gas_limit = 30_000_000,
            },
            .tx = .{
                .caller = config.caller,
                .gas_limit = config.gas_limit,
                .transact_to = .{ .call = config.target },
                .value = config.value,
                .nonce = config.nonce,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    return .{ .host = host, .mem_db = mem_db };
}

test "CREATE address derivation produces deterministic unique addresses" {
    const sender: [20]u8 = [_]u8{0x0a} ** 20;

    const addr_nonce_0 = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 0 });
    const addr_nonce_1 = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 1 });

    try testing.expect(!std.mem.eql(u8, &addr_nonce_0, &addr_nonce_1));

    const addr_nonce_0_again = try EVM.deriveCreateAddress(testing.allocator, .{ sender, 0 });
    try testing.expectEqualSlices(u8, &addr_nonce_0, &addr_nonce_0_again);
}

test "CREATE2 address derivation uses salt and init code hash" {
    const sender: [20]u8 = [_]u8{0x0b} ** 20;
    const salt: u256 = 12345;
    const init_code = &[_]u8{ 0x60, 0x00, 0x60, 0x00, 0xf3 };

    const addr_salt_a = EVM.deriveCreate2Address(sender, salt, init_code);
    const addr_salt_b = EVM.deriveCreate2Address(sender, salt + 1, init_code);

    try testing.expect(!std.mem.eql(u8, &addr_salt_a, &addr_salt_b));

    const addr_salt_a_again = EVM.deriveCreate2Address(sender, salt, init_code);
    try testing.expectEqualSlices(u8, &addr_salt_a, &addr_salt_a_again);
}

test "EVM initializes with empty call stack and return data" {
    var fixture = try createTestEnvironment(.{});
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
    try testing.expectEqual(@as(usize, 0), vm.return_data.len);
}

test "EVM max call stack depth is 1024" {
    try testing.expectEqual(@as(usize, 1024), EVM.MAX_CALL_STACK_DEPTH);
}

test "executeTransaction succeeds with simple PUSH ADD STOP bytecode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
    try testing.expect(result.gas_used > 0);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "executeTransaction returns data correctly via RETURN opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.store_and_return,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    try testing.expectEqual(@as(u8, 0x42), result.output[31]);
}

test "executeTransaction executes complex arithmetic correctly" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.complex_arithmetic,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    try testing.expectEqual(@as(u8, 0x10), result.output[31]);
}

test "executeTransaction persists storage changes on success" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.sstore_sload_return,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(u8, 0x42), result.output[31]);

    const stored_value = try fixture.host.journal.sload(TestAddresses.target, 0);
    try testing.expectEqual(@as(u256, 0x42), stored_value.data);
}

test "executeTransaction reverts storage changes on REVERT" {
    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var code_hash: [32]u8 = undefined;
    Keccak256.hash(TestBytecode.sstore_then_revert, &code_hash, .{});

    var target_info: AccountInfo = .{
        .code_hash = code_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(TestBytecode.sstore_then_revert) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &target_info);
    try mem_db.addAccountStorage(TestAddresses.target, 0, 100);

    var journal: JournaledState = undefined;
    journal.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal,
        .env = .{
            .config = .{ .spec_id = .SHANGHAI, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 100_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.InterpreterReverted, result);

    const stored_value = try host.journal.sload(TestAddresses.target, 0);
    try testing.expectEqual(@as(u256, 100), stored_value.data);
}

test "executeTransaction transfers value from caller to target" {
    const transfer_value: u256 = 1000;
    const initial_caller_balance: u256 = 10_000;

    var fixture = try createTestEnvironment(.{
        .value = transfer_value,
        .caller_balance = initial_caller_balance,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);

    const caller_account = fixture.host.journal.state.get(TestAddresses.caller).?;
    const target_account = fixture.host.journal.state.get(TestAddresses.target).?;

    try testing.expectEqual(initial_caller_balance - transfer_value, caller_account.info.balance);
    try testing.expectEqual(transfer_value, target_account.info.balance);
}

test "executeTransaction with zero value does not modify balances" {
    const initial_balance: u256 = 10_000;

    var fixture = try createTestEnvironment(.{
        .value = 0,
        .caller_balance = initial_balance,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);

    const caller_account = fixture.host.journal.state.get(TestAddresses.caller).?;
    try testing.expectEqual(initial_balance, caller_account.info.balance);
}

test "executeTransaction succeeds when nonce matches account state" {
    var fixture = try createTestEnvironment(.{
        .nonce = 5,
        .caller_nonce = 5,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
}

test "executeTransaction fails with InvalidNonce when nonce does not match" {
    var fixture = try createTestEnvironment(.{
        .nonce = 10,
        .caller_nonce = 5,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.InvalidNonce, result);
}

test "executeTransaction skips nonce validation when nonce is null" {
    var fixture = try createTestEnvironment(.{
        .nonce = null,
        .caller_nonce = 999,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
}

test "executeTransaction fails with InsufficientBalance when balance is too low" {
    var fixture = try createTestEnvironment(.{
        .value = 10_000,
        .caller_balance = 100,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.InsufficientBalance, result);
}

test "executeTransaction succeeds when balance check is disabled" {
    var fixture = try createTestEnvironment(.{
        .value = 10_000,
        .caller_balance = 100,
        .disable_balance_check = true,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
}

test "executeTransaction returns InterpreterReverted on REVERT opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.revert_empty,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.InterpreterReverted, result);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "executeTransaction returns InvalidOpcode on INVALID opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.invalid_opcode,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.InvalidInstructionOpcode, result);
}

test "executeTransaction returns StackUnderflow on stack underflow" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.stack_underflow,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.StackUnderflow, result);
}

test "executeTransaction returns OutOfGas when gas is exhausted" {
    var fixture = try createTestEnvironment(.{
        .gas_limit = 1,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.OutOfGas, result);
}

test "executeTransaction tracks gas consumption correctly" {
    var fixture = try createTestEnvironment(.{
        .gas_limit = 100_000,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
    try testing.expect(result.gas_used > 0);
    try testing.expect(result.gas_used < 100_000);
}

test "executeTransaction succeeds when calling EOA with no code" {
    const eoa_target: [20]u8 = [_]u8{0xEE} ** 20;

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 10_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var target_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 0,
    };
    try mem_db.addAccountInfo(eoa_target, &target_info);

    var journal: JournaledState = undefined;
    journal.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal,
        .env = .{
            .config = .{ .spec_id = .SHANGHAI, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 21_000,
                .transact_to = .{ .call = eoa_target },
                .value = 1000,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);

    const caller_account = host.journal.state.get(TestAddresses.caller).?;
    const target_account = host.journal.state.get(eoa_target).?;

    try testing.expectEqual(@as(u256, 9_000), caller_account.info.balance);
    try testing.expectEqual(@as(u256, 1_000), target_account.info.balance);
    try testing.expectEqual(@as(u64, 1), caller_account.info.nonce);
    try testing.expectEqual(@as(u64, 0), target_account.info.nonce);
}

test "ExecutionResult deinit frees output buffer" {
    const output = try testing.allocator.alloc(u8, 10);
    @memset(output, 0xab);

    var result = EVM.ExecutionResult{
        .status = .stopped,
        .output = output,
        .gas_used = 100,
        .gas_refunded = 0,
    };

    result.deinit(testing.allocator);
}

test "CallFrame deinit releases all resources" {
    var plain_db: PlainDatabase = .{};

    var journal: JournaledState = undefined;
    journal.init(testing.allocator, .SHANGHAI, plain_db.database());
    defer journal.deinit();

    var host: JournaledHost = .{
        .journal = journal,
        .env = .{ .config = .{ .spec_id = .SHANGHAI } },
    };

    const contract = try Contract.init(
        testing.allocator,
        &[_]u8{},
        .{ .raw = @constCast(&[_]u8{ 0x60, 0x01, 0x00 }) },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );

    var interpreter: evm_mod.Interpreter = undefined;
    try interpreter.init(testing.allocator, &contract, host.host(), .{});

    var frame: EVM.CallFrame = .{
        .contract = contract,
        .interpreter = interpreter,
        .return_memory_offset = .{ 0, 0 },
        .is_create = false,
        .checkpoint = .{ .journal_checkpoint = 0, .logs_checkpoint = 0 },
    };

    frame.deinit(testing.allocator);
}

// Complex nested CALL test
test "nested CALL executes target bytecode and returns data to parent" {
    // Setup: Parent calls Child which returns 0x42
    // Child stores 0x42 at memory[0], returns 32 bytes
    // Parent receives return data, stores it, and returns it

    const child_address: [20]u8 = [_]u8{0xCC} ** 20;

    // Child bytecode: store 0x42 at memory[0], return 32 bytes
    const child_code = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0x00
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 0x20
        0x60, 0x00, // PUSH1 0x00
        0xf3, // RETURN
    };

    // Parent bytecode: CALL child, then return the child's return data
    // CALL args order on stack (top to bottom): gas, addr, value, argsOffset, argsSize, retOffset, retSize
    // But CALL pops in order: gas, addr, value, argsOffset, argsSize, retOffset, retSize
    // So we push in reverse order
    const parent_code = &[_]u8{
        // Push CALL arguments in reverse order (stack is LIFO)
        0x60, 0x20, // PUSH1 0x20 (retSize)
        0x60, 0x00, // PUSH1 0x00 (retOffset)
        0x60, 0x00, // PUSH1 0x00 (argsSize)
        0x60, 0x00, // PUSH1 0x00 (argsOffset)
        0x60, 0x00, // PUSH1 0x00 (value)
        0x73, // PUSH20 (child address)
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0x62, 0x0F, 0xFF, 0xFF, // PUSH3 0x0FFFFF (gas - enough for subcall)
        0xF1, // CALL
        0x50, // POP (discard success flag)
        0x60, 0x20, // PUSH1 0x20 (return 32 bytes)
        0x60, 0x00, // PUSH1 0x00 (from offset 0)
        0xF3, // RETURN
    };

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var parent_hash: [32]u8 = undefined;
    Keccak256.hash(parent_code, &parent_hash, .{});
    var parent_info: AccountInfo = .{
        .code_hash = parent_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(parent_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    var child_hash: [32]u8 = undefined;
    Keccak256.hash(child_code, &child_hash, .{});
    var child_info: AccountInfo = .{
        .code_hash = child_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(child_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(child_address, &child_info);

    journal_state.init(testing.allocator, .LATEST, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 500_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    try testing.expectEqual(@as(u8, 0x42), result.output[31]);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "subcall revert preserves parent state and reverts child changes" {
    // Parent stores 0x11 at slot 0, calls Child which stores 0x22 then reverts.
    // Parent then stores 0x33 at slot 1, returns.
    // Expected: slot 0 = 0x11, slot 1 = 0x33, child's 0x22 write is reverted.

    const child_address: [20]u8 = [_]u8{0xCC} ** 20;

    // Child: SSTORE 0x22 at slot 0, then REVERT
    const child_code = &[_]u8{
        0x60, 0x22, // PUSH1 0x22
        0x60, 0x00, // PUSH1 0x00
        0x55, // SSTORE
        0x60, 0x00, // PUSH1 0x00
        0x60, 0x00, // PUSH1 0x00
        0xFD, // REVERT
    };

    // Parent: SSTORE 0x11 at slot 0, CALL child, SSTORE 0x33 at slot 1, STOP
    const parent_code = &[_]u8{
        0x60, 0x11, // PUSH1 0x11
        0x60, 0x00, // PUSH1 0x00
        0x55, // SSTORE (slot 0 = 0x11)
        // CALL child
        0x60, 0x00, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x00, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 child
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0xCC,
        0x62, 0x0F, 0xFF, 0xFF, // PUSH3 0x0FFFFF (gas)
        0xF1, // CALL
        0x50, // POP success
        0x60, 0x33, // PUSH1 0x33
        0x60, 0x01, // PUSH1 0x01
        0x55, // SSTORE (slot 1 = 0x33)
        0x00, // STOP
    };

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var parent_hash: [32]u8 = undefined;
    Keccak256.hash(parent_code, &parent_hash, .{});
    var parent_info: AccountInfo = .{
        .code_hash = parent_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(parent_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    var child_hash: [32]u8 = undefined;
    Keccak256.hash(child_code, &child_hash, .{});
    var child_info: AccountInfo = .{
        .code_hash = child_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(child_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(child_address, &child_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 500_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);

    // Verify parent's storage: slot 0 should be 0x11 (not 0x22 from reverted child)
    const slot0 = try host.journal.sload(TestAddresses.target, 0);
    try testing.expectEqual(@as(u256, 0x11), slot0.data);

    // Verify slot 1 = 0x33
    const slot1 = try host.journal.sload(TestAddresses.target, 1);
    try testing.expectEqual(@as(u256, 0x33), slot1.data);
}

test "CALL to non-existent code succeeds with value transfer only" {
    // Calling an address with no code should succeed (value transfer only)
    // Parent: CALL empty_address (0xEE..EE) with value, check return value, STOP
    const parent_code = &[_]u8{
        0x60, 0x00, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x00, // argsSize
        0x60, 0x00, // argsOffset
        0x61, 0x03, 0xE8, // value = 1000
        0x73, // PUSH20 empty_address
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0xEE,
        0x62, 0x0F, 0xFF, 0xFF, // PUSH3 gas
        0xF1, // CALL
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE (store success flag)
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var parent_hash: [32]u8 = undefined;
    Keccak256.hash(parent_code, &parent_hash, .{});
    var parent_info: AccountInfo = .{
        .code_hash = parent_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(parent_code) },
        .balance = 10_000,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 500_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);
    // Success flag should be 1
    try testing.expectEqual(@as(u8, 1), result.output[31]);
}

test "CREATE deploys new contract and pushes address to stack" {
    // Parent executes CREATE with init code that returns 0xDEADBEEF
    // Init code: PUSH4 0xDEADBEEF, PUSH1 0, MSTORE, PUSH1 4, PUSH1 28, RETURN

    const init_code = &[_]u8{
        0x63, 0xDE, 0xAD, 0xBE, 0xEF, // PUSH4 0xDEADBEEF
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x04, // PUSH1 4 (return 4 bytes)
        0x60, 0x1C, // PUSH1 28 (offset to last 4 bytes of word)
        0xF3, // RETURN
    };

    // Parent: push init code to memory, CREATE, return created address
    var parent_code_buf: [100]u8 = undefined;
    var idx: usize = 0;

    // PUSH init_code bytes to memory
    parent_code_buf[idx] = 0x6C; // PUSH13 (init code is 13 bytes)
    idx += 1;
    @memcpy(parent_code_buf[idx .. idx + 13], init_code);
    idx += 13;
    parent_code_buf[idx] = 0x60; // PUSH1 0
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0x52; // MSTORE
    idx += 1;

    // CREATE: value=0, offset=19 (32-13), size=13
    parent_code_buf[idx] = 0x60; // PUSH1 13 (size)
    idx += 1;
    parent_code_buf[idx] = 0x0D;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 19 (offset = 32 - 13)
    idx += 1;
    parent_code_buf[idx] = 0x13;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 0 (value)
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0xF0; // CREATE
    idx += 1;

    // Return created address
    parent_code_buf[idx] = 0x60; // PUSH1 0
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0x52; // MSTORE
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 32
    idx += 1;
    parent_code_buf[idx] = 0x20;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 0
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0xF3; // RETURN
    idx += 1;

    const parent_code = parent_code_buf[0..idx];

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var parent_hash: [32]u8 = undefined;
    Keccak256.hash(parent_code, &parent_hash, .{});
    var parent_info: AccountInfo = .{
        .code_hash = parent_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(parent_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    journal_state.init(testing.allocator, .LATEST, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 500_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);

    // The returned address should be non-zero (CREATE succeeded)
    var addr_bytes: [20]u8 = undefined;
    @memcpy(&addr_bytes, result.output[12..32]);
    const addr_as_int = std.mem.readInt(u160, &addr_bytes, .big);
    try testing.expect(addr_as_int != 0);

    // Verify the created contract has the expected code (0xDEADBEEF)
    const created_account = host.journal.state.get(addr_bytes);
    try testing.expect(created_account != null);
}

test "CREATE2 uses salt for deterministic address" {
    // Parent executes CREATE2 with salt=0x1234
    const init_code = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x01, // PUSH1 1
        0x60, 0x1F, // PUSH1 31
        0xF3, // RETURN (return 1 byte: 0x42)
    };

    // Parent: push init code, CREATE2 with salt, return address
    var parent_code_buf: [120]u8 = undefined;
    var idx: usize = 0;

    // Store init code in memory
    parent_code_buf[idx] = 0x69; // PUSH10 (init code is 10 bytes)
    idx += 1;
    @memcpy(parent_code_buf[idx .. idx + 10], init_code);
    idx += 10;
    parent_code_buf[idx] = 0x60;
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0x52; // MSTORE
    idx += 1;

    // CREATE2: value=0, offset=22, size=10, salt=0x1234
    parent_code_buf[idx] = 0x61; // PUSH2 0x1234 (salt)
    idx += 1;
    parent_code_buf[idx] = 0x12;
    idx += 1;
    parent_code_buf[idx] = 0x34;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 10 (size)
    idx += 1;
    parent_code_buf[idx] = 0x0A;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 22 (offset = 32 - 10)
    idx += 1;
    parent_code_buf[idx] = 0x16;
    idx += 1;
    parent_code_buf[idx] = 0x60; // PUSH1 0 (value)
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0xF5; // CREATE2
    idx += 1;

    // Return address
    parent_code_buf[idx] = 0x60;
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0x52;
    idx += 1;
    parent_code_buf[idx] = 0x60;
    idx += 1;
    parent_code_buf[idx] = 0x20;
    idx += 1;
    parent_code_buf[idx] = 0x60;
    idx += 1;
    parent_code_buf[idx] = 0x00;
    idx += 1;
    parent_code_buf[idx] = 0xF3;
    idx += 1;

    const parent_code = parent_code_buf[0..idx];

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var parent_hash: [32]u8 = undefined;
    Keccak256.hash(parent_code, &parent_hash, .{});
    var parent_info: AccountInfo = .{
        .code_hash = parent_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(parent_code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 500_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.returned, result.status);

    // Verify address is deterministic by computing expected CREATE2 address
    var addr_bytes: [20]u8 = undefined;
    @memcpy(&addr_bytes, result.output[12..32]);
    const expected_addr = EVM.deriveCreate2Address(TestAddresses.target, 0x1234, init_code);
    try testing.expectEqualSlices(u8, &expected_addr, &addr_bytes);
}

test "gas refund respects disable_gas_refund config" {
    // SSTORE 0 (clear storage) should generate refund, but disable_gas_refund=true should zero it
    const code = &[_]u8{
        0x60, 0x01, // PUSH1 1
        0x60, 0x00, // PUSH1 0
        0x55, // SSTORE (set slot 0 = 1)
        0x60, 0x00, // PUSH1 0
        0x60, 0x00, // PUSH1 0
        0x55, // SSTORE (clear slot 0 = 0, generates refund)
        0x00, // STOP
    };

    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    var code_hash: [32]u8 = undefined;
    Keccak256.hash(code, &code_hash, .{});
    var target_info: AccountInfo = .{
        .code_hash = code_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(code) },
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &target_info);

    journal_state.init(testing.allocator, .LATEST, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{
                .spec_id = .LATEST,
                .disable_gas_refund = true,
                .disable_block_gas_limit = true,
            },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = 100_000,
                .transact_to = .{ .call = TestAddresses.target },
                .value = 0,
                .nonce = 0,
                .max_fee_per_blob_gas = null,
            },
        },
    };

    var vm: EVM = undefined;
    defer {
        vm.deinit();
        host.journal.deinit();
        mem_db.deinit();
    }

    vm.init(testing.allocator, host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.stopped, result.status);
    try testing.expectEqual(@as(i64, 0), result.gas_refunded);
}
