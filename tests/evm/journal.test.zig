const constants = @import("zabi").utils.constants;
const database = evm.database;
const evm = @import("zabi").evm;
const journal = evm.journal;
const std = @import("std");
const testing = std.testing;

const AccountInfo = evm.host.AccountInfo;
const JournaledState = journal.JournaledState;
const MemoryDatabase = database.MemoryDatabase;
const PlainDatabase = database.PlainDatabase;

test "It can start" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());
}

test "Account" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .created = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = "" },
                .balance = 0,
            },
        });
        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .cold = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = "" },
                .balance = 0,
            },
        });

        const account = try journal_db.loadAccount([_]u8{1} ** 20);
        const account_1 = try journal_db.loadAccount([_]u8{2} ** 20);

        try testing.expectEqual(account.cold, false);
        try testing.expectEqual(account.data.status.created, 1);
        try testing.expectEqual(account.data.status.cold, 0);

        try testing.expectEqual(account_1.cold, true);
        try testing.expectEqual(account.data.status.cold, 0);

        try testing.expectEqualSlices(u8, &account.data.info.code_hash, &constants.EMPTY_HASH);
        try testing.expectEqual(account.data.info.code.?.raw.len, 0);

        try testing.expectEqualSlices(u8, &account_1.data.info.code_hash, &constants.EMPTY_HASH);
        try testing.expectEqual(account_1.data.info.code.?.raw.len, 0);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        const account = try journal_db.loadAccount([_]u8{1} ** 20);

        try testing.expectEqual(account.cold, true);
        try testing.expectEqual(account.data.status.non_existent, 1);
        try testing.expectEqual(account.data.status.cold, 0);

        try testing.expectEqualSlices(u8, &account.data.info.code_hash, &constants.EMPTY_HASH);
        try testing.expectEqual(account.data.info.code.?.raw.len, 0);
    }
    {
        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        var mem_db: MemoryDatabase = undefined;
        defer mem_db.deinit();

        try mem_db.init(testing.allocator);

        journal_db.init(testing.allocator, .LATEST, mem_db.database());

        const account = try journal_db.loadAccount([_]u8{1} ** 20);

        try testing.expectEqual(account.cold, true);
        try testing.expectEqual(account.data.status.loaded, 1);
        try testing.expectEqual(account.data.status.cold, 0);

        try testing.expectEqualSlices(u8, &account.data.info.code_hash, &constants.EMPTY_HASH);
        try testing.expectEqual(account.data.info.code.?.raw.len, 0);
    }
}

test "Load code" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        const account = try journal_db.loadCode([_]u8{1} ** 20);

        try testing.expectEqual(account.cold, true);
        try testing.expectEqual(account.data.status.non_existent, 1);
        try testing.expectEqual(account.data.status.cold, 0);

        try testing.expectEqualSlices(u8, &account.data.info.code_hash, &constants.EMPTY_HASH);
        try testing.expectEqual(account.data.info.code.?.raw.len, 0);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = 0,
                .code = .{ .raw = @constCast("69420") },
                .balance = 0,
            },
        });

        const account = try journal_db.loadCode([_]u8{1} ** 20);

        try testing.expectEqual(account.cold, false);
        try testing.expectEqual(account.data.status.loaded, 1);

        try testing.expectEqualSlices(u8, &account.data.info.code_hash, &[_]u8{0} ** 32);
        try testing.expectEqual(account.data.info.code.?.raw.len, 0);
    }
}

test "Checkpoint" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());

    const checkpoint = try journal_db.checkpoint();

    try testing.expectEqual(0, checkpoint.logs_checkpoint);
    try testing.expectEqual(0, checkpoint.journal_checkpoint);
    try testing.expectEqual(1, journal_db.depth);

    const checkpoint_1 = try journal_db.checkpoint();

    try testing.expectEqual(0, checkpoint_1.logs_checkpoint);
    try testing.expectEqual(0, checkpoint_1.journal_checkpoint);
    try testing.expectEqual(2, journal_db.depth);

    journal_db.commitCheckpoint();
    try testing.expectEqual(1, journal_db.depth);
}

test "Update Spec Id" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());
    journal_db.updateSpecId(.CANCUN);

    try testing.expectEqual(17, @intFromEnum(journal_db.spec));
}

test "Touch account" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());

    try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
        .status = .{ .loaded = 1 },
        .storage = .init(testing.allocator),
        .info = .{
            .code_hash = [_]u8{0} ** 32,
            .nonce = 0,
            .code = .{ .raw = @constCast("69420") },
            .balance = 0,
        },
    });

    try journal_db.touchAccount([_]u8{1} ** 20);
    try testing.expectEqual(1, journal_db.state.get([_]u8{1} ** 20).?.status.loaded);
    try testing.expectEqual(1, journal_db.state.get([_]u8{1} ** 20).?.status.touched);

    const list = journal_db.journal.items[0];
    try testing.expect(list == .account_touched);
}

test "Set code" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());

    try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
        .status = .{ .loaded = 1 },
        .storage = .init(testing.allocator),
        .info = .{
            .code_hash = [_]u8{0} ** 32,
            .nonce = 0,
            .code = .{ .raw = @constCast("69420") },
            .balance = 0,
        },
    });

    var buffer: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash("6001", &buffer, .{});

    try journal_db.setCode([_]u8{1} ** 20, .{ .raw = @constCast("6001") });
    try testing.expectEqualSlices(u8, &buffer, &journal_db.state.get([_]u8{1} ** 20).?.info.code_hash);
    try testing.expectEqualStrings(journal_db.state.get([_]u8{1} ** 20).?.info.code.?.raw, "6001");

    const list = journal_db.journal.items[1];
    try testing.expect(list == .code_changed);
}

test "Set code and hash" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LATEST, plain.database());

    try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
        .status = .{ .loaded = 1 },
        .storage = .init(testing.allocator),
        .info = .{
            .code_hash = [_]u8{0} ** 32,
            .nonce = 0,
            .code = .{ .raw = @constCast("69420") },
            .balance = 0,
        },
    });

    try journal_db.setCodeAndHash([_]u8{1} ** 20, .{ .raw = @constCast("6001") }, [_]u8{69} ** 32);
    try testing.expectEqualSlices(u8, &[_]u8{69} ** 32, &journal_db.state.get([_]u8{1} ** 20).?.info.code_hash);
    try testing.expectEqualStrings(journal_db.state.get([_]u8{1} ** 20).?.info.code.?.raw, "6001");

    const list = journal_db.journal.items[1];
    try testing.expect(list == .code_changed);
}

test "Increment account nonce" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = 0,
                .code = .{ .raw = @constCast("69420") },
                .balance = 0,
            },
        });

        const nonce = try journal_db.incrementAccountNonce([_]u8{1} ** 20);
        try testing.expectEqual(1, journal_db.state.get([_]u8{1} ** 20).?.info.nonce);
        try testing.expectEqual(1, nonce.?);

        const list = journal_db.journal.items[0];
        try testing.expect(list == .nonce_changed);
    }

    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 0,
            },
        });

        const nonce = try journal_db.incrementAccountNonce([_]u8{1} ** 20);
        try testing.expectEqual(null, nonce);
    }
}

test "Transfer" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.transfer([_]u8{1} ** 20, [_]u8{2} ** 20, 0);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 69420,
            },
        });
        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 42069,
            },
        });

        try journal_db.transfer([_]u8{1} ** 20, [_]u8{2} ** 20, 100);

        try testing.expectEqual(journal_db.state.get([_]u8{1} ** 20).?.info.balance, 69320);
        try testing.expectEqual(journal_db.state.get([_]u8{2} ** 20).?.info.balance, 42169);

        const list = journal_db.journal.items[journal_db.journal.items.len - 1];
        try testing.expect(list == .balance_transfer);
        try testing.expectEqual(journal_db.journal.items.len, 3);
    }
}

test "Create account" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = @constCast("") },
                .balance = 69420,
            },
        });
        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = undefined,
                .nonce = 0,
                .code = .{ .raw = @constCast("") },
                .balance = 42069,
            },
        });

        try testing.expectError(error.OutOfFunds, journal_db.createAccountCheckpoint([_]u8{1} ** 20, [_]u8{2} ** 20, 100_000));
        try testing.expectError(error.CreateCollision, journal_db.createAccountCheckpoint([_]u8{1} ** 20, [_]u8{2} ** 20, 1));
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = @constCast("") },
                .balance = 69420,
            },
        });
        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = @constCast("") },
                .balance = 42069,
            },
        });

        const checkpoint = try journal_db.createAccountCheckpoint([_]u8{1} ** 20, [_]u8{2} ** 20, 100);

        try testing.expectEqual(0, checkpoint.journal_checkpoint);
        try testing.expectEqual(0, checkpoint.logs_checkpoint);
        try testing.expectEqual(1, journal_db.depth);
        try testing.expectEqual(1, journal_db.state.get([_]u8{2} ** 20).?.status.created);
        try testing.expectEqual(null, journal_db.state.get([_]u8{2} ** 20).?.info.code);
        try testing.expectEqual(1, journal_db.state.get([_]u8{2} ** 20).?.info.nonce);

        const list = journal_db.journal.items[journal_db.journal.items.len - 1];
        try testing.expect(list == .balance_transfer);
        try testing.expectEqual(journal_db.journal.items.len, 3);
    }
}

test "Sload/Sstore" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 69420,
            },
        });

        const value = try journal_db.sload([_]u8{1} ** 20, 0);

        try testing.expectEqual(0, value.data);

        const list = journal_db.journal.items[journal_db.journal.items.len - 1];
        try testing.expect(list == .storage_warmed);
        try testing.expectEqual(journal_db.journal.items.len, 1);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        var storage = std.AutoHashMap(u256, evm.host.StorageSlot).init(testing.allocator);
        try storage.put(0, .{ .is_cold = true, .present_value = 69, .original_value = 69 });
        try storage.put(1, .{ .is_cold = false, .present_value = 69, .original_value = 69 });

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = storage,
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 69420,
            },
        });

        const value = try journal_db.sload([_]u8{1} ** 20, 0);

        try testing.expectEqual(69, value.data);
        try testing.expectEqual(true, value.cold);

        const value_1 = try journal_db.sload([_]u8{1} ** 20, 1);

        try testing.expectEqual(69, value_1.data);
        try testing.expectEqual(false, value_1.cold);

        const list = journal_db.journal.items[journal_db.journal.items.len - 1];
        try testing.expect(list == .storage_warmed);
        try testing.expectEqual(1, journal_db.journal.items.len);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .loaded = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = [_]u8{0} ** 32,
                .nonce = std.math.maxInt(u64),
                .code = .{ .raw = @constCast("69420") },
                .balance = 69420,
            },
        });

        const value = try journal_db.sstore([_]u8{1} ** 20, 0, 69);

        try testing.expectEqual(0, value.data.present_value);
        try testing.expectEqual(0, value.data.original_value);
        try testing.expectEqual(69, value.data.new_value);
        try testing.expectEqual(true, value.cold);

        const list = journal_db.journal.items[journal_db.journal.items.len - 1];
        try testing.expect(list == .storage_changed);
        try testing.expectEqual(2, journal_db.journal.items.len);

        const value_1 = try journal_db.sstore([_]u8{1} ** 20, 1, 0);

        try testing.expectEqual(0, value_1.data.present_value);
        try testing.expectEqual(0, value_1.data.original_value);
        try testing.expectEqual(0, value_1.data.new_value);
        try testing.expectEqual(true, value_1.cold);
    }
}

test "Tload/Tstore" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        const value = journal_db.tload([_]u8{1} ** 20, 0);

        try testing.expectEqual(0, value);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.transient_storage.put(testing.allocator, .{ [_]u8{2} ** 20, 69 }, 420);

        try journal_db.tstore([_]u8{1} ** 20, 0, 69);
        try journal_db.tstore([_]u8{2} ** 20, 69, 69420);

        try testing.expectEqual(69, journal_db.transient_storage.get(.{ [_]u8{1} ** 20, 0 }).?);
        try testing.expectEqual(69420, journal_db.transient_storage.get(.{ [_]u8{2} ** 20, 69 }).?);

        try journal_db.tstore([_]u8{3} ** 20, 0, 0);

        try journal_db.tstore([_]u8{2} ** 20, 69, 0);
        try testing.expectEqual(null, journal_db.transient_storage.get(.{ [_]u8{2} ** 20, 69 }));
    }
}

test "Self destruct" {
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LATEST, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .non_existent = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 0,
                .code = .{ .raw = @constCast("") },
                .balance = 0,
            },
        });

        const value = try journal_db.selfDestruct([_]u8{1} ** 20, [_]u8{2} ** 20);

        try testing.expectEqual(false, value.data.had_value);
        try testing.expectEqual(false, value.data.previously_destroyed);
        try testing.expectEqual(false, value.data.target_exists);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LONDON, plain.database());

        try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
            .status = .{ .created = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 1,
                .code = .{ .raw = @constCast("") },
                .balance = 0,
            },
        });
        try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
            .status = .{ .non_existent = 1 },
            .storage = .init(testing.allocator),
            .info = .{
                .code_hash = constants.EMPTY_HASH,
                .nonce = 1,
                .code = .{ .raw = @constCast("") },
                .balance = 0,
            },
        });

        const value = try journal_db.selfDestruct([_]u8{1} ** 20, [_]u8{2} ** 20);

        try testing.expectEqual(false, value.data.had_value);
        try testing.expectEqual(false, value.data.previously_destroyed);
        try testing.expectEqual(true, value.data.target_exists);
    }
    {
        var plain: PlainDatabase = .{};

        var journal_db: JournaledState = undefined;
        defer journal_db.deinit();

        journal_db.init(testing.allocator, .LONDON, plain.database());

        const value = try journal_db.selfDestruct([_]u8{1} ** 20, [_]u8{1} ** 20);

        try testing.expectEqual(false, value.data.had_value);
        try testing.expectEqual(false, value.data.previously_destroyed);
        try testing.expectEqual(false, value.data.target_exists);
    }
}

test "Revert" {
    var plain: PlainDatabase = .{};

    var journal_db: JournaledState = undefined;
    defer journal_db.deinit();

    journal_db.init(testing.allocator, .LONDON, plain.database());
    try journal_db.state.put(testing.allocator, [_]u8{1} ** 20, .{
        .status = .{ .loaded = 1 },
        .storage = .init(testing.allocator),
        .info = .{
            .code_hash = constants.EMPTY_HASH,
            .nonce = 0,
            .code = .{ .raw = @constCast("") },
            .balance = 69420,
        },
    });
    try journal_db.state.put(testing.allocator, [_]u8{2} ** 20, .{
        .status = .{ .non_existent = 1 },
        .storage = .init(testing.allocator),
        .info = .{
            .code_hash = constants.EMPTY_HASH,
            .nonce = 0,
            .code = .{ .raw = @constCast("") },
            .balance = 0,
        },
    });
    try journal_db.transient_storage.put(testing.allocator, .{ [_]u8{1} ** 20, 1 }, 45);

    const checkpoint = try journal_db.checkpoint();

    {
        try journal_db.tstore([_]u8{1} ** 20, 1, 69);
        try journal_db.transfer([_]u8{1} ** 20, [_]u8{2} ** 20, 100);
        _ = try journal_db.sload([_]u8{1} ** 20, 0);
        _ = try journal_db.sstore([_]u8{1} ** 20, 1, 69);
        _ = try journal_db.createAccountCheckpoint([_]u8{2} ** 20, [_]u8{1} ** 20, 100);
        try journal_db.setCode([_]u8{1} ** 20, .{ .raw = @constCast("6001") });
        _ = try journal_db.incrementAccountNonce([_]u8{1} ** 20);
        _ = try journal_db.selfDestruct([_]u8{1} ** 20, [_]u8{2} ** 20);
    }

    try testing.expectEqual(12, journal_db.journal.items.len);

    try journal_db.revertCheckpoint(checkpoint);
    try testing.expectEqual(1, journal_db.depth);
    try testing.expectEqual(0, journal_db.journal.items.len);
}
