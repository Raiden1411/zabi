const database = evm.database;
const evm = @import("zabi").evm;
const std = @import("std");
const testing = std.testing;

const AccountInfo = evm.journal.AccountInfo;
const MemoryDatabase = database.MemoryDatabase;
const PlainDatabase = database.PlainDatabase;

test "It can start" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());
}

test "Add contract" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());

    var bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, "f26e8bc5b6055af33a88e81c46bfc941616e29daae6cdc588fe7efa51b93c733");

    var account_info: AccountInfo = .{
        .code = .{ .raw = @constCast("6001") },
        .nonce = 69,
        .balance = 0,
        .code_hash = database.EMPTY_HASH,
    };

    try db.addContract(&account_info);
    try testing.expectEqualSlices(u8, &account_info.code_hash, &bytes);
}

test "Blockhash" {
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());
        const hash = try MemoryDatabase.blockHash(&db, 69);

        var bytes: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&bytes, "db37925934a3d3177db64e11f5e0156ceb8a756fee58ded16e549afa607ddb1d");

        try testing.expectEqualSlices(u8, &hash, &bytes);
        try testing.expectEqualSlices(u8, &hash, &db.block_hashes.get(69).?);
    }
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        var bytes: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&bytes, "db37925934a3d3177db64e11f5e0156ceb8a756fee58ded16e549afa607ddb1d");

        try db.init(testing.allocator, plain_db.database());
        try db.block_hashes.put(testing.allocator, 69, bytes);

        const hash = try MemoryDatabase.blockHash(&db, 69);

        try testing.expectEqualSlices(u8, &hash, &bytes);
        try testing.expectEqualSlices(u8, &hash, &db.block_hashes.get(69).?);
    }
}

test "CodeByHash" {
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());
        const code = try MemoryDatabase.codeByHash(&db, [_]u8{0} ** 32);

        try testing.expect(code == .raw);
    }
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());
        const code = try MemoryDatabase.codeByHash(&db, [_]u8{69} ** 32);

        try testing.expect(code == .raw);
    }
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());
        try db.contracts.put(testing.allocator, [_]u8{1} ** 32, .{ .raw = @constCast("6001") });
        const code = try MemoryDatabase.codeByHash(&db, [_]u8{1} ** 32);

        try testing.expect(code == .raw);
        try testing.expectEqualStrings(code.raw, "6001");
    }
}

test "Storage" {
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());
        const value = try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 69);

        try testing.expectEqual(value, 0);
    }
    {
        var plain_db: PlainDatabase = .{};

        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator, plain_db.database());

        const db_account: database.DatabaseAccount = .{
            .info = .{
                .balance = 0,
                .nonce = 0,
                .code_hash = [_]u8{0} ** 32,
                .code = null,
            },
            .account_state = .none,
            .storage = .init(testing.allocator),
        };

        try db.account.put(testing.allocator, [_]u8{1} ** 20, db_account);
        const value = try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 69);

        try testing.expectEqual(value, 0);
    }
}

test "Basic" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());

    try testing.expectEqual((try MemoryDatabase.basic(&db, [_]u8{1} ** 20)).?.nonce, 0);
}

test "Add account info" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());

    const db_account: database.DatabaseAccount = .{
        .info = .{
            .balance = 0,
            .nonce = 0,
            .code_hash = [_]u8{0} ** 32,
            .code = null,
        },
        .account_state = .none,
        .storage = .init(testing.allocator),
    };

    try db.account.put(testing.allocator, [_]u8{1} ** 20, db_account);

    var account_info: AccountInfo = .{
        .code = null,
        .nonce = 69,
        .balance = 0,
        .code_hash = [_]u8{0} ** 32,
    };
    try db.addAccountInfo([_]u8{1} ** 20, &account_info);
    try testing.expectEqual(db.account.get([_]u8{1} ** 20).?.info.nonce, 69);
}

test "Add account storage" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());

    var account_info: AccountInfo = .{
        .code = null,
        .nonce = 69,
        .balance = 0,
        .code_hash = [_]u8{0} ** 32,
    };
    try db.addAccountInfo([_]u8{1} ** 20, &account_info);

    var db_other: MemoryDatabase = undefined;
    defer db_other.deinit();

    try db_other.init(testing.allocator, db.database());
    try db_other.addAccountStorage([_]u8{1} ** 20, 69, 420);

    try testing.expectEqual((try MemoryDatabase.basic(&db_other, [_]u8{1} ** 20)).?.nonce, 69);
    try testing.expectEqual((try MemoryDatabase.storage(&db_other, [_]u8{1} ** 20, 69)), 420);
}

test "Update account storage" {
    var plain_db: PlainDatabase = .{};

    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator, plain_db.database());

    var account_info: AccountInfo = .{
        .code = null,
        .nonce = 69,
        .balance = 0,
        .code_hash = [_]u8{0} ** 32,
    };
    try db.addAccountInfo([_]u8{1} ** 20, &account_info);

    var db_other: MemoryDatabase = undefined;
    defer db_other.deinit();

    try db_other.init(testing.allocator, db.database());

    var storage = std.AutoHashMap(u256, u256).init(testing.allocator);
    try storage.put(69, 420);

    try db_other.updateAccountStorage([_]u8{1} ** 20, storage);

    try testing.expectEqual((try MemoryDatabase.basic(&db_other, [_]u8{1} ** 20)).?.nonce, 69);
    try testing.expectEqual((try MemoryDatabase.storage(&db_other, [_]u8{1} ** 20, 69)), 420);
    try testing.expectEqual((try MemoryDatabase.storage(&db_other, [_]u8{1} ** 20, 1)), 0);
}
