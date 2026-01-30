const bytecode = @import("bytecode.zig");
const constants = @import("zabi-utils").constants;
const host = @import("host.zig");
const std = @import("std");
const types = @import("zabi-types");

const Account = host.Account;
const AccountInfo = host.AccountInfo;
const Address = types.ethereum.Address;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AutoHashMap = std.AutoHashMap;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const Bytecode = bytecode.Bytecode;
const Hash = types.ethereum.Hash;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Log = types.log.Log;

/// Generic interface for implementing a database.
pub const Database = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Loads the account information associated to an address.
        basic: *const fn (self: *anyopaque, address: Address) anyerror!?AccountInfo,
        /// Gets the block hash from a given block number
        codeByHash: *const fn (self: *anyopaque, code_hash: Hash) anyerror!Bytecode,
        /// Gets the code of an `address` and if that address is cold.
        storage: *const fn (self: *anyopaque, address: Address, index: u256) anyerror!u256,
        /// Gets the code hash of an `address` and if that address is cold.
        blockHash: *const fn (self: *anyopaque, number: u64) anyerror!Hash,
    };

    /// Loads the account information associated to an address.
    pub inline fn basic(self: Self, address: Address) anyerror!?AccountInfo {
        return self.vtable.basic(self.ptr, address);
    }

    /// Gets the block hash from a given block number
    pub inline fn codeByHash(self: Self, code_hash: Hash) anyerror!Bytecode {
        return self.vtable.codeByHash(self.ptr, code_hash);
    }

    /// Gets the code of an `address` and if that address is cold.
    pub inline fn storage(self: Self, address: Address, index: u256) anyerror!u256 {
        return self.vtable.storage(self.ptr, address, index);
    }

    /// Gets the code hash of an `address` and if that address is cold.
    pub inline fn blockHash(self: Self, number: u64) anyerror!Hash {
        return self.vtable.blockHash(self.ptr, number);
    }
};

/// The state of the database account.
pub const AccountState = enum {
    not_existing,
    touched,
    storage_cleared,
    none,
};

/// Representation of an account in the database.
pub const DatabaseAccount = struct {
    info: AccountInfo,
    account_state: AccountState,
    storage: AutoHashMap(u256, u256),
};

/// A implementation of the `Database` interface.
///
/// This stores all changes in memory all clears all changes once a
/// program exits execution.
pub const MemoryDatabase = struct {
    const Self = @This();

    /// Set of possible error when loading an account.
    pub const AccountLoadError = BasicErrors || error{AccountNonExistent};

    /// Set of possible basic database errors.
    pub const BasicErrors = Allocator.Error || error{UnexpectedError};

    /// Hashmap of account associated with their addresses.
    account: AutoHashMapUnmanaged(Address, DatabaseAccount),
    /// The allocator that managed any allocated memory.
    allocator: Allocator,
    /// Hashmap of block numbers and block_hashes.
    block_hashes: AutoHashMapUnmanaged(u256, Hash),
    /// Hashmap of block_hashes and their associated bytecode.
    contracts: AutoHashMapUnmanaged(Hash, Bytecode),
    /// Inner fallback database.
    db: Database,
    /// List of emitted logs.
    logs: ArrayListUnmanaged(Log),

    /// Sets the initial state of the database.
    pub fn init(
        self: *Self,
        allocator: Allocator,
        db: Database,
    ) Allocator.Error!void {
        var contracts: AutoHashMapUnmanaged(Hash, Bytecode) = .empty;
        errdefer contracts.deinit(allocator);

        try contracts.put(allocator, [_]u8{0} ** 32, .{ .raw = "" });
        try contracts.put(allocator, constants.EMPTY_HASH, .{ .raw = "" });

        self.* = .{
            .account = .empty,
            .allocator = allocator,
            .block_hashes = .empty,
            .contracts = contracts,
            .db = db,
            .logs = .empty,
        };
    }

    /// Clears any allocated memory by this database
    /// and the storage accounts.
    pub fn deinit(self: *Self) void {
        var iter_acc = self.account.valueIterator();
        while (iter_acc.next()) |entries|
            entries.storage.deinit();

        var code_iter = self.contracts.valueIterator();
        while (code_iter.next()) |entries|
            entries.deinit(self.allocator);

        self.account.deinit(self.allocator);
        self.block_hashes.deinit(self.allocator);
        self.contracts.deinit(self.allocator);
        self.logs.deinit(self.allocator);

        self.* = undefined;
    }

    /// Returns the implementation of the `Database` interface.
    pub fn database(self: *Self) Database {
        return .{
            .ptr = self,
            .vtable = &.{
                .blockHash = blockHash,
                .storage = storage,
                .basic = basic,
                .codeByHash = codeByHash,
            },
        };
    }

    /// Adds the contract code of an account into the `contracts` hashmap.
    pub fn addContract(
        self: *Self,
        account: *AccountInfo,
    ) Allocator.Error!void {
        if (account.code) |code| {
            if (code.getCodeBytes().len != 0) {
                if (@as(u256, @bitCast(account.code_hash)) == @as(u256, @bitCast(constants.EMPTY_HASH))) {
                    var hash: Hash = undefined;
                    Keccak256.hash(code.getCodeBytes(), &hash, .{});

                    account.code_hash = hash;
                }

                try self.contracts.put(self.allocator, account.code_hash, code);
            }
        }

        if (@as(u256, @bitCast(account.code_hash)) == 0)
            account.code_hash = constants.EMPTY_HASH;
    }

    /// Adds the account information to the account associated with the provided address.
    pub fn addAccountInfo(
        self: *Self,
        address: Address,
        account: *AccountInfo,
    ) Allocator.Error!void {
        try self.addContract(account);
        const db_account = self.account.getPtr(address);

        if (db_account) |acc| {
            acc.info = account.*;
            return;
        }

        const new_db_account: DatabaseAccount = .{
            .info = account.*,
            .account_state = .none,
            .storage = .init(self.allocator),
        };

        try self.account.put(self.allocator, address, new_db_account);
    }

    /// Updates the account storage for the given slot index with the provided value.
    pub fn addAccountStorage(
        self: *Self,
        address: Address,
        slot: u256,
        value: u256,
    ) AccountLoadError!void {
        var db_acc = try self.loadAccount(address);

        try db_acc.storage.put(slot, value);
    }

    /// Loads the account information from the database.
    pub fn basic(
        self: *anyopaque,
        address: Address,
    ) BasicErrors!?AccountInfo {
        const db_self: *MemoryDatabase = @ptrCast(@alignCast(self));

        if (db_self.account.get(address)) |acc|
            return acc.info;

        const db_info = db_self.db.basic(address) catch return error.UnexpectedError;

        const account_info: DatabaseAccount = if (db_info) |info|
            .{
                .info = info,
                .account_state = .none,
                .storage = .init(db_self.allocator),
            }
        else
            .{
                .info = .{
                    .balance = 0,
                    .nonce = 0,
                    .code_hash = constants.EMPTY_HASH,
                    .code = .{ .raw = @constCast("") },
                },
                .account_state = .not_existing,
                .storage = .init(db_self.allocator),
            };

        try db_self.account.put(db_self.allocator, address, account_info);

        return account_info.info;
    }

    /// Gets the associated bytecode to the provided `code_hash`.
    pub fn codeByHash(
        self: *anyopaque,
        code_hash: Hash,
    ) error{UnexpectedError}!Bytecode {
        const db_self: *MemoryDatabase = @ptrCast(@alignCast(self));

        if (db_self.contracts.get(code_hash)) |code|
            return code;

        return db_self.db.codeByHash(code_hash) catch error.UnexpectedError;
    }

    /// Get the value in an account's storage slot.
    ///
    /// It is assumed that account is already loaded.
    pub fn storage(
        self: *anyopaque,
        address: Address,
        index: u256,
    ) BasicErrors!u256 {
        const db_self: *MemoryDatabase = @ptrCast(@alignCast(self));

        if (db_self.account.getPtr(address)) |account| {
            if (account.storage.get(index)) |value|
                return value;

            switch (account.account_state) {
                .storage_cleared,
                .not_existing,
                => return 0,
                else => {
                    const slot = db_self.db.storage(address, index) catch return error.UnexpectedError;

                    try account.storage.put(index, slot);

                    return slot;
                },
            }
        }

        const db_info = db_self.db.basic(address) catch return error.UnexpectedError;

        if (db_info) |info| {
            const slot = db_self.db.storage(address, index) catch return error.UnexpectedError;

            var db_account: DatabaseAccount = .{
                .info = info,
                .account_state = .none,
                .storage = .init(db_self.allocator),
            };

            try db_account.storage.put(index, slot);
            try db_self.account.put(db_self.allocator, address, db_account);

            return slot;
        }

        const db_account: DatabaseAccount = .{
            .info = .{
                .balance = 0,
                .nonce = 0,
                .code_hash = constants.EMPTY_HASH,
                .code = .{ .raw = @constCast("") },
            },
            .account_state = .not_existing,
            .storage = .init(db_self.allocator),
        };

        try db_self.account.put(db_self.allocator, address, db_account);

        return 0;
    }

    /// Gets the associated block_hashes from the provided number.
    pub fn blockHash(
        self: *anyopaque,
        number: u64,
    ) BasicErrors!Hash {
        const db_self: *MemoryDatabase = @ptrCast(@alignCast(self));

        if (db_self.block_hashes.get(number)) |hash|
            return hash;

        const db_hash = db_self.db.blockHash(number) catch return error.UnexpectedError;
        try db_self.block_hashes.put(db_self.allocator, number, db_hash);

        return db_hash;
    }

    /// Commits all of the changes to the database.
    pub fn commit(
        self: *Self,
        changes: AutoHashMapUnmanaged(Address, Account),
    ) AccountLoadError!void {
        const iter = changes.iterator();

        while (iter.next()) |entry| {
            if (entry.value_ptr.status.touched == 0)
                continue;

            if (entry.value_ptr.status.self_destructed != 0) {
                var db_acc = try self.loadAccount(entry.key_ptr.*);
                db_acc.storage.clearAndFree();
                db_acc.account_state = .not_existing;
                db_acc.info = .{
                    .code_hash = constants.EMPTY_HASH,
                    .code = .{ .raw = @constCast("") },
                    .nonce = 0,
                    .balance = 0,
                };

                continue;
            }

            try self.addContract(entry.value_ptr);

            var db_acc = try self.loadAccount(entry.key_ptr.*);
            db_acc.info = entry.value_ptr.info;

            db_acc.account_state = state: {
                if (entry.value_ptr.status.created != 0) {
                    db_acc.storage.clearAndFree();
                    break :state .storage_cleared;
                }

                if (db_acc.account_state != .storage_cleared)
                    break :state .touched;

                break :state .storage_cleared;
            };

            try db_acc.storage.ensureUnusedCapacity(entry.value_ptr.storage.capacity());

            const iter_storage = entry.value_ptr.storage.iterator();
            defer entry.value_ptr.storage.deinit();

            while (iter_storage.next()) |entries|
                db_acc.storage.putAssumeCapacity(entries.key_ptr.*, entries.value_ptr.*);
        }
    }

    /// Updates the storage from a given account.
    pub fn updateAccountStorage(
        self: *Self,
        address: Address,
        account_storage: AutoHashMap(u256, u256),
    ) AccountLoadError!void {
        var db_acc = try self.loadAccount(address);
        // Clear the previously allocated memory.
        db_acc.storage.deinit();

        db_acc.storage = account_storage;
        db_acc.account_state = .storage_cleared;
    }

    /// Loads an account from the database.
    pub fn loadAccount(
        self: *Self,
        address: Address,
    ) AccountLoadError!*DatabaseAccount {
        if (self.account.getEntry(address)) |db_acc|
            return db_acc.value_ptr;

        const account_info = (self.db.basic(address) catch return error.UnexpectedError) orelse return error.AccountNonExistent;
        const db_acc: DatabaseAccount = .{
            .info = account_info,
            .storage = .init(self.allocator),
            .account_state = .none,
        };

        try self.account.put(self.allocator, address, db_acc);

        return self.account.getEntry(address).?.value_ptr;
    }
};

/// Empty database used only for testing.
pub const PlainDatabase = struct {
    empty: void = {},

    pub fn basic(_: *anyopaque, _: Address) !?AccountInfo {
        return null;
    }

    pub fn codeByHash(_: *anyopaque, _: Hash) !Bytecode {
        return .{ .raw = "" };
    }

    pub fn storage(_: *anyopaque, _: Address, _: u256) !u256 {
        return 0;
    }

    pub fn blockHash(_: *anyopaque, number: u64) !Hash {
        var buffer: [@sizeOf(u64)]u8 = undefined;
        const slice = try std.fmt.bufPrint(&buffer, "{d}", .{number});

        var hash: Hash = undefined;
        Keccak256.hash(slice, &hash, .{});
        return hash;
    }

    pub fn database(self: *@This()) Database {
        return .{
            .ptr = self,
            .vtable = &.{
                .basic = basic,
                .codeByHash = codeByHash,
                .storage = storage,
                .blockHash = blockHash,
            },
        };
    }
};
