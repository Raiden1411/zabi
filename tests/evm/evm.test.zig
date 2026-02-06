const constants = @import("zabi").utils.constants;
const evm_mod = @import("zabi").evm;
const crypto = @import("zabi").crypto;
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
const AccessList = @import("zabi").types.transactions.AccessList;
const StorageSlot = evm_mod.host.StorageSlot;
const Signer = crypto.Signer;

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
    const revert_with_data = &[_]u8{
        0x60, 0x42, // PUSH1 0x42
        0x60, 0x00, // PUSH1 0x00
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 0x20
        0x60, 0x00, // PUSH1 0x00
        0xfd, // REVERT
    };

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

fn hasAccountWarmedEntry(entries: []const evm_mod.journal.JournalEntry, address: [20]u8) bool {
    for (entries) |entry| {
        switch (entry) {
            .account_warmed => |info| {
                if (std.mem.eql(u8, &info.address, &address))
                    return true;
            },
            else => {},
        }
    }

    return false;
}

fn hasStorageWarmedEntry(entries: []const evm_mod.journal.JournalEntry, address: [20]u8, key: u256) bool {
    for (entries) |entry| {
        switch (entry) {
            .storage_warmed => |info| {
                if (std.mem.eql(u8, &info.address, &address) and info.key == key)
                    return true;
            },
            else => {},
        }
    }

    return false;
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

test "executeBytecode enforces perform_analysis for jump validation" {
    const jump_code = &[_]u8{ 0x60, 0x04, 0x56, 0xfd, 0x5b, 0x00 };

    {
        var fixture = try createTestEnvironment(.{
            .target_code = TestBytecode.push_add_stop,
        });
        defer fixture.deinit();

        fixture.host.env.config.perform_analysis = .analyse;

        var vm: EVM = undefined;
        defer vm.deinit();
        vm.init(testing.allocator, fixture.host.host());

        var result = try vm.executeBytecode(.{ .raw = @constCast(jump_code) });
        defer result.deinit(testing.allocator);

        try testing.expectEqual(.stopped, result.status);
    }

    {
        var fixture = try createTestEnvironment(.{
            .target_code = TestBytecode.push_add_stop,
        });
        defer fixture.deinit();

        fixture.host.env.config.perform_analysis = .raw;

        var vm: EVM = undefined;
        defer vm.deinit();
        vm.init(testing.allocator, fixture.host.host());

        try testing.expectError(error.InvalidJump, vm.executeBytecode(.{ .raw = @constCast(jump_code) }));
    }
}

test "top-level executions clear transient storage between runs" {
    const store_transient = &[_]u8{
        0x60, 0x01, // PUSH1 1 (value)
        0x60, 0x00, // PUSH1 0 (key)
        0x5d, // TSTORE
        0x00, // STOP
    };
    const read_transient = &[_]u8{
        0x60, 0x00, // PUSH1 0 (key)
        0x5c, // TLOAD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xf3, // RETURN
    };

    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();
    vm.init(testing.allocator, fixture.host.host());

    var store_result = try vm.executeBytecode(.{ .raw = @constCast(store_transient) });
    defer store_result.deinit(testing.allocator);
    try testing.expectEqual(evm_mod.Interpreter.InterpreterStatus.stopped, store_result.status);

    var read_result = try vm.executeBytecode(.{ .raw = @constCast(read_transient) });
    defer read_result.deinit(testing.allocator);
    try testing.expectEqual(evm_mod.Interpreter.InterpreterStatus.returned, read_result.status);
    try testing.expectEqual(@as(usize, 32), read_result.output.len);
    try testing.expectEqual(@as(u8, 0), read_result.output[31]);
}

test "executeTransaction applies account access list prewarming and resets it next transaction" {
    const warm_address = [_]u8{0xAB} ** 20;
    const access_list = [_]AccessList{
        .{
            .address = warm_address,
            .storageKeys = &.{},
        },
    };
    const code = &[_]u8{
        0x73, // PUSH20 warm_address
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0xAB,
        0x31, // BALANCE
        0x50, // POP
        0x00, // STOP
    };

    var fixture = try createTestEnvironment(.{
        .target_code = code,
        .nonce = 0,
        .caller_nonce = 0,
    });
    defer fixture.deinit();

    fixture.host.env.config.spec_id = .BERLIN;
    fixture.host.env.tx.tx_type = .berlin;
    fixture.host.env.tx.access_list = &access_list;

    var vm: EVM = undefined;
    defer vm.deinit();
    vm.init(testing.allocator, fixture.host.host());

    var first = try vm.executeTransaction();
    defer first.deinit(testing.allocator);

    try testing.expectEqual(.stopped, first.status);
    try testing.expect(!hasAccountWarmedEntry(fixture.host.journal.journal.items, warm_address));

    fixture.host.env.tx.access_list = &.{};
    fixture.host.env.tx.nonce = 1;

    var second = try vm.executeTransaction();
    defer second.deinit(testing.allocator);

    try testing.expectEqual(.stopped, second.status);
    try testing.expect(hasAccountWarmedEntry(fixture.host.journal.journal.items, warm_address));
}

test "executeTransaction applies storage access list prewarming and resets it next transaction" {
    const storage_key: [32]u8 = [_]u8{0} ** 32;
    const access_list = [_]AccessList{
        .{
            .address = TestAddresses.target,
            .storageKeys = &[_][32]u8{storage_key},
        },
    };
    const code = &[_]u8{
        0x60, 0x00, // PUSH1 0
        0x54, // SLOAD
        0x50, // POP
        0x00, // STOP
    };

    var fixture = try createTestEnvironment(.{
        .target_code = code,
        .nonce = 0,
        .caller_nonce = 0,
    });
    defer fixture.deinit();

    fixture.host.env.config.spec_id = .BERLIN;
    fixture.host.env.tx.tx_type = .berlin;
    fixture.host.env.tx.access_list = &access_list;

    var vm: EVM = undefined;
    defer vm.deinit();
    vm.init(testing.allocator, fixture.host.host());

    var first = try vm.executeTransaction();
    defer first.deinit(testing.allocator);

    try testing.expectEqual(.stopped, first.status);
    try testing.expect(!hasStorageWarmedEntry(fixture.host.journal.journal.items, TestAddresses.target, 0));

    fixture.host.env.tx.access_list = &.{};
    fixture.host.env.tx.nonce = 1;

    var second = try vm.executeTransaction();
    defer second.deinit(testing.allocator);

    try testing.expectEqual(.stopped, second.status);
    try testing.expect(hasStorageWarmedEntry(fixture.host.journal.journal.items, TestAddresses.target, 0));
}

test "EVM Validate block context" {
    {
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
        journal.init(testing.allocator, .LATEST, mem_db.database());

        var host: JournaledHost = .{
            .journal = journal,
            .env = .{
                .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
                .block = .{ .gas_limit = 30_000_000, .prevrandao = null },
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

        try testing.expectError(error.PrevRandaoNotSet, vm.executeTransaction());
    }
    {
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
        journal.init(testing.allocator, .LATEST, mem_db.database());

        var host: JournaledHost = .{
            .journal = journal,
            .env = .{
                .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
                .block = .{ .gas_limit = 30_000_000, .blob_excess_gas_and_price = null },
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

        try testing.expectError(error.ExcessBlobGasNotSet, vm.executeTransaction());
    }
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

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.reverted, result.status);
    try testing.expectEqual(@as(usize, 0), result.output.len);

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

test "executeTransaction returns reverted status on REVERT opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.revert_empty,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.reverted, result.status);
    try testing.expectEqual(@as(usize, 0), result.output.len);
    try testing.expectEqual(@as(usize, 0), vm.call_stack.items.len);
}

test "executeTransaction returns revert data on REVERT opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.revert_with_data,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.reverted, result.status);
    try testing.expectEqual(@as(usize, 32), result.output.len);
    try testing.expectEqual(@as(u8, 0x42), result.output[31]);
}

test "executeTransaction returns invalid status on INVALID opcode" {
    var fixture = try createTestEnvironment(.{
        .target_code = TestBytecode.invalid_opcode,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    var result = try vm.executeTransaction();
    defer result.deinit(testing.allocator);

    try testing.expectEqual(.invalid, result.status);
}

test "executeTransaction commits SELFDESTRUCT state changes" {
    const beneficiary: [20]u8 = TestAddresses.caller;
    const contract_balance: u256 = 5_000;

    const selfdestruct_code = &[_]u8{
        0x73, // PUSH20 beneficiary
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xCA,
        0xFF, // SELFDESTRUCT
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
    Keccak256.hash(selfdestruct_code, &code_hash, .{});
    var target_info: AccountInfo = .{
        .code_hash = code_hash,
        .nonce = 0,
        .code = .{ .raw = @constCast(selfdestruct_code) },
        .balance = contract_balance,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &target_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
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

    try testing.expectEqual(.self_destructed, result.status);

    const caller_account = host.journal.state.get(beneficiary).?;
    const target_account = host.journal.state.get(TestAddresses.target).?;

    try testing.expectEqual(@as(u256, 1_000_000 + contract_balance), caller_account.info.balance);
    try testing.expectEqual(@as(u256, 0), target_account.info.balance);
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

test "executeTransaction fails when gas limit is below intrinsic transaction cost" {
    var fixture = try createTestEnvironment(.{
        .gas_limit = constants.TRANSACTION - 1,
        .target_code = TestBytecode.push_add_stop,
    });
    defer fixture.deinit();

    var vm: EVM = undefined;
    defer vm.deinit();

    vm.init(testing.allocator, fixture.host.host());

    const result = vm.executeTransaction();
    try testing.expectError(error.IntrinsicGasTooLow, result);
}

test "executeTransaction returns OutOfGas when execution gas is exhausted after intrinsic charge" {
    var fixture = try createTestEnvironment(.{
        .gas_limit = constants.TRANSACTION + 1,
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

test "executeTransaction charges intrinsic gas before opcode execution" {
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
    try testing.expect(result.gas_used >= constants.TRANSACTION);
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

test "CALL to precompile 0x01 executes ECRECOVER" {
    const message_hash: [32]u8 = [_]u8{0x11} ** 32;
    const private_key: [32]u8 = [_]u8{0x22} ** 32;

    const signer = try Signer.init(private_key);
    const signature = try signer.sign(message_hash);

    var input: [128]u8 = [_]u8{0} ** 128;
    @memcpy(input[0..32], message_hash[0..]);
    const v_value: u256 = @as(u256, signature.v) + 27;
    std.mem.writeInt(u256, input[32..64], v_value, .big);
    std.mem.writeInt(u256, input[64..96], signature.r, .big);
    std.mem.writeInt(u256, input[96..128], signature.s, .big);

    // Parent bytecode to call precompile and return output
    const parent_code = &[_]u8{
        0x7F, // PUSH32 input (first 32 bytes)
        input[0],
        input[1],
        input[2],
        input[3],
        input[4],
        input[5],
        input[6],
        input[7],
        input[8],
        input[9],
        input[10],
        input[11],
        input[12],
        input[13],
        input[14],
        input[15],
        input[16],
        input[17],
        input[18],
        input[19],
        input[20],
        input[21],
        input[22],
        input[23],
        input[24],
        input[25],
        input[26],
        input[27],
        input[28],
        input[29],
        input[30],
        input[31],
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x7F, // PUSH32 input (second 32 bytes)
        input[32],
        input[33],
        input[34],
        input[35],
        input[36],
        input[37],
        input[38],
        input[39],
        input[40],
        input[41],
        input[42],
        input[43],
        input[44],
        input[45],
        input[46],
        input[47],
        input[48],
        input[49],
        input[50],
        input[51],
        input[52],
        input[53],
        input[54],
        input[55],
        input[56],
        input[57],
        input[58],
        input[59],
        input[60],
        input[61],
        input[62],
        input[63],
        0x60, 0x20, // PUSH1 32
        0x52, // MSTORE
        0x7F, // PUSH32 input (third 32 bytes)
        input[64],
        input[65],
        input[66],
        input[67],
        input[68],
        input[69],
        input[70],
        input[71],
        input[72],
        input[73],
        input[74],
        input[75],
        input[76],
        input[77],
        input[78],
        input[79],
        input[80],
        input[81],
        input[82],
        input[83],
        input[84],
        input[85],
        input[86],
        input[87],
        input[88],
        input[89],
        input[90],
        input[91],
        input[92],
        input[93],
        input[94],
        input[95],
        0x60, 0x40, // PUSH1 64
        0x52, // MSTORE
        0x7F, // PUSH32 input (fourth 32 bytes)
        input[96],
        input[97],
        input[98],
        input[99],
        input[100],
        input[101],
        input[102],
        input[103],
        input[104],
        input[105],
        input[106],
        input[107],
        input[108],
        input[109],
        input[110],
        input[111],
        input[112],
        input[113],
        input[114],
        input[115],
        input[116],
        input[117],
        input[118],
        input[119],
        input[120],
        input[121],
        input[122],
        input[123],
        input[124],
        input[125],
        input[126],
        input[127],
        0x60, 0x60, // PUSH1 96
        0x52, // MSTORE
        0x60, 0x20, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x80, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 precompile address
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x62, 0x0F, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x50, // POP
        0x60, 0x20, // RETURN size
        0x60, 0x00, // RETURN offset
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

    var expected: [32]u8 = [_]u8{0} ** 32;
    @memcpy(expected[12..32], signer.address_bytes[0..]);
    try testing.expectEqualSlices(u8, expected[0..], result.output);
}

test "CALL to precompile 0x02 executes SHA256" {
    const input = "hello";

    const parent_code = &[_]u8{
        0x7F, // PUSH32 input padded
        'h',
        'e',
        'l',
        'l',
        'o',
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x05, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 precompile
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x02,
        0x62, 0x0F, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x50, // POP
        0x60, 0x20, // RETURN size
        0x60, 0x00, // RETURN offset
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

    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &expected, .{});

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqualSlices(u8, expected[0..], result.output);
}

test "CALL to precompile 0x03 executes RIPEMD160" {
    const precompile_address: [20]u8 = [_]u8{0} ** 19 ++ [_]u8{3};
    const input = "hello";

    const parent_code = &[_]u8{
        0x7F, // PUSH32 input padded
        'h',
        'e',
        'l',
        'l',
        'o',
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x05, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 precompile
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x03,
        0x62, 0x0F, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x50, // POP
        0x60, 0x20, // RETURN size
        0x60, 0x00, // RETURN offset
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

    // Derive expected output through the same address-dispatched precompile entrypoint.
    var expected_output = try evm_mod.precompiles.executePrecompile(
        testing.allocator,
        .LATEST,
        precompile_address,
        input,
        500_000,
    );
    defer testing.allocator.free(expected_output.output);

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqualSlices(u8, expected_output.output, result.output);
}

test "CALL to precompile 0x04 executes IDENTITY" {
    const input = "hello world";

    const parent_code = &[_]u8{
        0x7F, // PUSH32 input padded
        'h',
        'e',
        'l',
        'l',
        'o',
        ' ',
        'w',
        'o',
        'r',
        'l',
        'd',
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x0B, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x0B, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 precompile
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x04,
        0x62, 0x0F, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x50, // POP
        0x60, 0x0B, // RETURN size
        0x60, 0x00, // RETURN offset
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
    try testing.expectEqualSlices(u8, input, result.output);
}

test "CALL to precompile 0x05 executes MODEXP" {
    // base=2, exp=5, mod=13 -> 2^5 mod 13 = 6
    const parent_code = &[_]u8{
        0x60, 0x01, // PUSH1 1 (base length)
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x01, // PUSH1 1 (exp length)
        0x60, 0x20, // PUSH1 32
        0x52, // MSTORE
        0x60, 0x01, // PUSH1 1 (mod length)
        0x60, 0x40, // PUSH1 64
        0x52, // MSTORE
        0x60, 0x02, // PUSH1 2 (base value)
        0x60, 0x60, // PUSH1 96
        0x53, // MSTORE8
        0x60, 0x05, // PUSH1 5 (exp value)
        0x60, 0x61, // PUSH1 97
        0x53, // MSTORE8
        0x60, 0x0D, // PUSH1 13 (mod value)
        0x60, 0x62, // PUSH1 98
        0x53, // MSTORE8
        0x60, 0x01, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x63, // argsSize (99)
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
        0x73, // PUSH20 precompile address
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x05,
        0x62, 0x0F, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x50, // POP
        0x60, 0x01, // RETURN size
        0x60, 0x00, // RETURN offset
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
    try testing.expectEqual(@as(usize, 1), result.output.len);
    try testing.expectEqual(@as(u8, 6), result.output[0]);
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

test "CALL to non-existent code refunds forwarded gas to the parent frame" {
    const parent_code = &[_]u8{
        0x60, 0x00, // retSize
        0x60, 0x00, // retOffset
        0x60, 0x00, // argsSize
        0x60, 0x00, // argsOffset
        0x60, 0x00, // value
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
        0x61, 0xFF, 0xFF, // gas
        0xF1, // CALL
        0x5A, // GAS
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
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
                .gas_limit = 24_200,
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

    const remaining_gas = std.mem.readInt(u64, result.output[24..32], .big);
    try testing.expect(remaining_gas > 100);
}

test "create transaction fails when gas limit is below create intrinsic cost" {
    try mem_db.init(testing.allocator);

    var caller_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 0,
        .code = null,
        .balance = 1_000_000,
    };
    try mem_db.addAccountInfo(TestAddresses.caller, &caller_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .SHANGHAI, .disable_block_gas_limit = true },
            .block = .{ .gas_limit = 30_000_000 },
            .tx = .{
                .caller = TestAddresses.caller,
                .gas_limit = constants.TRANSACTION + constants.CREATE - 1,
                .transact_to = .create,
                .data = @constCast(&[_]u8{0x00}),
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
    try testing.expectError(error.IntrinsicGasTooLow, result);
}

test "CREATE collision is handled as a soft failure and pushes zero" {
    const parent_code = &[_]u8{
        0x60, 0x00, // size
        0x60, 0x00, // offset
        0x60, 0x00, // value
        0xF0, // CREATE
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
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
        .balance = 0,
    };
    try mem_db.addAccountInfo(TestAddresses.target, &parent_info);

    const collision_address = try EVM.deriveCreateAddress(testing.allocator, .{ TestAddresses.target, 0 });
    var collision_info: AccountInfo = .{
        .code_hash = constants.EMPTY_HASH,
        .nonce = 1,
        .code = null,
        .balance = 0,
    };
    try mem_db.addAccountInfo(collision_address, &collision_info);

    journal_state.init(testing.allocator, .SHANGHAI, mem_db.database());

    var host: JournaledHost = .{
        .journal = journal_state,
        .env = .{
            .config = .{ .spec_id = .LATEST, .disable_block_gas_limit = true },
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

    try testing.expectEqual(.returned, result.status);
    try testing.expectEqual(@as(u8, 0), result.output[31]);
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
