const bytecode = @import("bytecode.zig");
const journal = @import("journal.zig");
const std = @import("std");
const types = @import("zabi-types");

const AccountInfo = journal.AccountInfo;
const Address = types.ethereum.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AutoHashMap = std.AutoHashMap;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const Bytecode = bytecode.Bytecode;
const Hash = types.ethereum.Hash;
const Log = types.log.Log;

const EMPTY_HASH = [_]u8{ 0xc5, 0xd2, 0x46, 0x01, 0x86, 0xf7, 0x23, 0x3c, 0x92, 0x7e, 0x7d, 0xb2, 0xdc, 0xc7, 0x03, 0xc0, 0xe5, 0x00, 0xb6, 0x53, 0xca, 0x82, 0x27, 0x3b, 0x7b, 0xfa, 0xd8, 0x04, 0x5d, 0x85, 0xa4, 0x70 };

pub const Database = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        basic: *const fn (self: *anyopaque, address: Address) anyerror!?AccountInfo,
        /// Gets the block hash from a given block number
        codeByHash: *const fn (self: *anyopaque, code_hash: Hash) anyerror!Bytecode,
        /// Gets the code of an `address` and if that address is cold.
        storage: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!u256,
        /// Gets the code hash of an `address` and if that address is cold.
        blockHash: *const fn (self: *anyopaque, number: u64) anyerror!Hash,
    };

    pub inline fn basic(self: Self, address: Address) anyerror!?AccountInfo {
        return self.vtable.basic(self.ptr, address);
    }
    pub inline fn codeByHash(self: Self, code_hash: Hash) anyerror!Bytecode {
        return self.vtable.codeByHash(self.ptr, code_hash);
    }
    pub inline fn storage(self: Self, address: Address, index: u256) anyerror!u256 {
        return self.vtable.storage(self.ptr, address, index);
    }
    pub inline fn blockHash(self: Self, number: u64) anyerror!Hash {
        return self.vtable.blockHash(self.ptr, number);
    }
};

pub const AccountState = enum {
    not_existing,
    touched,
    storage_cleared,
    none,
};

pub const DatabaseAccount = struct {
    info: AccountInfo,
    account_state: AccountState,
    storage: AutoHashMap(u256, u256),
};

pub const MemoryDatabase = struct {
    const Self = @This();

    account: AutoHashMapUnmanaged(Address, DatabaseAccount),
    allocator: Allocator,
    block_hashes: AutoHashMapUnmanaged(u256, Hash),
    contracts: AutoHashMapUnmanaged(Hash, Bytecode),
    db: Database,
    logs: ArrayListUnmanaged(Log),

    pub fn init(self: *Self, allocator: Allocator, db: Database) Allocator.Error!void {
        var contracts: AutoHashMapUnmanaged(Hash, Bytecode) = .empty;

        try contracts.put(allocator, [_]u8{0} ** 32, .{ .raw = "" });
        try contracts.put(allocator, EMPTY_HASH, .{ .raw = "" });

        self.* = .{
            .account = .empty,
            .allocator = allocator,
            .block_hashes = .empty,
            .contracts = contracts,
            .db = db,
            .logs = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.account.deinit(self.allocator);
        self.block_hashes.deinit(self.allocator);
        self.contracts.deinit(self.allocator);
        self.logs.deinit(self.allocator);
    }

    pub fn database(self: *Self) Database {
        return .{
            .ptr = self,
            .vtable = .{
                .blockHash = blockHash,
                .storage = storage,
                .basic = basic,
                .codeByHash = codeByHash,
            },
        };
    }

    pub fn addContract(self: *Self, account: *AccountInfo) !void {
        if (account.code) |code| {
            if (code.getCodeBytes().len != 0) {
                if (@as(u256, @bitCast(account.code_hash)) == @as(u256, @bitCast(EMPTY_HASH))) {
                    var hash: Hash = undefined;
                    std.crypto.hash.sha3.Keccak256.hash(code.getCodeBytes(), &hash, .{});

                    account.code_hash = hash;
                }
                // TODO: Take ownership of the memory here.
                try self.contracts.put(account.code_hash, code);
            }
        }

        if (@as(u256, @bitCast(account.code_hash)) == 0)
            account.code_hash = EMPTY_HASH;
    }

    pub fn addAccountInfo(self: *Self, address: Address, account: *AccountInfo) !void {
        try self.addContract(account);
        const db_account = self.account.get(address);

        if (db_account) |*acc|
            acc.info = account.*;
    }

    pub fn addAccountStorage(
        self: *Self,
        address: Address,
        slot: u256,
        value: u256,
    ) !void {
        var db_acc = try self.loadAccount(address);
        try db_acc.storage.put(slot, value);
    }

    pub fn basic(self: *Self, address: Address) !AccountInfo {
        if (self.account.get(address)) |acc|
            return acc.info;

        const db_info = try self.db.basic(address);

        const account_info: AccountInfo = if (db_info) |info|
            .{
                .info = info,
                .account_state = .none,
                .storage = .init(self.allocator),
            }
        else
            .{
                .info = .{
                    .balance = 0,
                    .nonce = 0,
                    .code_hash = [_]u8{0} ** 32,
                    .bytecode = null,
                },
                .account_state = .not_existing,
                .storage = .init(self.allocator),
            };

        try self.account.put(self.allocator, address, account_info);

        return account_info;
    }

    pub fn codeByHash(self: *Self, code_hash: Hash) !Bytecode {
        if (self.contracts.get(code_hash)) |code| {
            // TODO: Make the caller own this memory
            return code;
        }

        const db_bytecode = try self.db.codeByHash(code_hash);

        // TODO: Make the caller own this memory
        return db_bytecode;
    }

    pub fn storage(self: *Self, address: Address, index: u256) !u256 {
        if (self.account.get(address)) |account| {
            if (account.storage.get(index)) |value|
                return value;

            switch (account.account_state) {
                .storage_cleared,
                .not_existing,
                => return 0,
                else => {
                    const slot = try self.db.storage(address, index);

                    try account.storage.put(index, slot);

                    return slot;
                },
            }
        }

        const db_info = try self.db.basic(address);

        if (db_info) |info| {
            const slot = try self.db.storage(address, index);

            const db_account: DatabaseAccount = .{
                .info = info,
                .account_state = .none,
                .storage = .init(self.allocator),
            };

            try db_account.storage.put(index, slot);
            try self.account.put(self.allocator, address, db_account);

            return slot;
        }

        const db_account: DatabaseAccount = .{
            .info = .{
                .balance = 0,
                .nonce = 0,
                .code_hash = [_]u8{0} ** 32,
                .bytecode = null,
            },
            .account_state = .not_existing,
            .storage = .init(self.allocator),
        };

        try self.account.put(self.allocator, address, db_account);

        return 0;
    }

    pub fn blockHash(self: *Self, number: u64) !Hash {
        if (self.block_hashes.get(number)) |hash|
            return hash;

        const db_hash = try self.db.blockHash(number);
        try self.block_hashes.put(self.allocator, number, db_hash);

        return db_hash;
    }

    pub fn commit(self: *Self, changes: AutoHashMapUnmanaged(Address, journal.Account)) !void {
        const iter = changes.iterator();

        while (iter.next()) |entry| {
            if (entry.value_ptr.status.touched == 0)
                continue;

            if (entry.value_ptr.status.self_destructed != 0) {
                var db_acc = try self.loadAccount(entry.key_ptr.*);
                db_acc.storage.clearAndFree();
                db_acc.account_state = .not_existing;
                db_acc.info = .{
                    .code_hash = [_]u8{0} ** 32,
                    .code = null,
                    .nonce = 0,
                    .balance = 0,
                };

                continue;
            }

            try self.addContract(entry.value_ptr);

            var db_acc = try self.loadAccount(entry.key_ptr.*);
            db_acc.info = entry.value_ptr.info;

            db_acc.account_state = blk: {
                if (entry.value_ptr.status.created != 0) {
                    db_acc.storage.clearAndFree();
                    break :blk .storage_cleared;
                }

                if (db_acc.account_state != .storage_cleared)
                    break :blk .touched;

                break :blk .storage_cleared;
            };

            try db_acc.storage.ensureUnusedCapacity(entry.value_ptr.storage.capacity());
            const iter_storage = entry.value_ptr.storage.iterator();
            // TODO: Check if it's necessary to deinit here.
            defer entry.value_ptr.storage.deinit();

            while (iter_storage.next()) |entries|
                db_acc.storage.putAssumeCapacity(entries.key_ptr.*, entries.value_ptr.*);
        }
    }

    pub fn updateAccountStorage(self: *Self, allocator: Allocator, address: Address, account_storage: AutoHashMap(u256, u256)) !void {
        var db_acc = try self.loadAccount(allocator, address);
        db_acc.storage = account_storage;
        db_acc.account_state = .storage_cleared;
    }

    pub fn loadAccount(self: *Self, address: Address) !DatabaseAccount {
        if (self.account.get(address)) |db_acc|
            return db_acc;

        const basic_acc = try self.db.basic(address) orelse return error.AccountNonExisten;
        const db_acc = DatabaseAccount{
            .info = basic_acc,
            .storage = AutoHashMap(u256, u256).init(self.allocator),
            .account_state = .none,
        };

        try self.account.put(self.allocator, db_acc);

        return db_acc;
    }
};
