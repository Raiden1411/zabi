const constants = @import("zabi").utils.constants;
const database = evm.database;
const evm = @import("zabi").evm;
const std = @import("std");
const testing = std.testing;

const Account = evm.database.DatabaseAccount;
const AccountInfo = evm.host.AccountInfo;
const MemoryDatabase = database.MemoryDatabase;
const PlainDatabase = database.PlainDatabase;

test "It can start" {
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);
}

test "Add contract" {
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);

    var bytes: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&bytes, "f26e8bc5b6055af33a88e81c46bfc941616e29daae6cdc588fe7efa51b93c733");

    var account_info: AccountInfo = .{
        .code = .{ .raw = @constCast("6001") },
        .nonce = 69,
        .balance = 0,
        .code_hash = constants.EMPTY_HASH,
    };

    try db.addContract(&account_info);
    try testing.expectEqualSlices(u8, &account_info.code_hash, &bytes);
}

test "Blockhash" {
    {
        var db: MemoryDatabase = undefined;
        defer db.deinit();

        var bytes: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&bytes, "db37925934a3d3177db64e11f5e0156ceb8a756fee58ded16e549afa607ddb1d");

        try db.init(testing.allocator);
        try db.block_hashes.put(testing.allocator, 69, bytes);

        const hash = try MemoryDatabase.blockHash(&db, 69);

        try testing.expectEqualSlices(u8, &hash, &bytes);
        try testing.expectEqualSlices(u8, &hash, &db.block_hashes.get(69).?);
    }
}

test "CodeByHash" {
    {
        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator);
        try db.contracts.put(testing.allocator, [_]u8{1} ** 32, .{ .raw = @constCast("6001") });
        const code = try MemoryDatabase.codeByHash(&db, [_]u8{1} ** 32);

        try testing.expect(code == .raw);
        try testing.expectEqualStrings(code.raw, "6001");
    }
}

test "Storage" {
    {
        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator);
        const value = try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 69);

        try testing.expectEqual(value, 0);
    }
    {
        var db: MemoryDatabase = undefined;
        defer db.deinit();

        try db.init(testing.allocator);

        const db_account: Account = .{
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
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);

    try testing.expectEqual((try MemoryDatabase.basic(&db, [_]u8{1} ** 20)).?.nonce, 0);
}

test "Add account info" {
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);

    const db_account: Account = .{
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
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);

    var account_info: AccountInfo = .{
        .code = null,
        .nonce = 69,
        .balance = 0,
        .code_hash = [_]u8{0} ** 32,
    };
    try db.addAccountInfo([_]u8{1} ** 20, &account_info);
    try db.addAccountStorage([_]u8{1} ** 20, 69, 420);

    try testing.expectEqual((try MemoryDatabase.basic(&db, [_]u8{1} ** 20)).?.nonce, 69);
    try testing.expectEqual((try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 69)), 420);
}

test "Update account storage" {
    var db: MemoryDatabase = undefined;
    defer db.deinit();

    try db.init(testing.allocator);

    var account_info: AccountInfo = .{
        .code = null,
        .nonce = 69,
        .balance = 0,
        .code_hash = [_]u8{0} ** 32,
    };
    try db.addAccountInfo([_]u8{1} ** 20, &account_info);
    var storage = std.AutoHashMap(u256, u256).init(testing.allocator);
    try storage.put(69, 420);

    try db.updateAccountStorage([_]u8{1} ** 20, storage);

    try testing.expectEqual((try MemoryDatabase.basic(&db, [_]u8{1} ** 20)).?.nonce, 69);
    try testing.expectEqual((try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 69)), 420);
    try testing.expectEqual((try MemoryDatabase.storage(&db, [_]u8{1} ** 20, 1)), 0);
}
